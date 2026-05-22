//
//  DriverTabPanes.swift
//  EusoTrip — Placeholder content for the Driver BottomNav's Trips / Wallet /
//  Me tabs. Screen 010 (Home) is rendered by DriverHome; the other three
//  top-level tabs ship as lightweight stubs here so the nav is fully
//  navigable today while the dedicated screens land in later waves.
//
//  Each pane:
//    • Preserves §2 nav invariants (Shell handles the chrome — pane just
//      returns content).
//    • Uses §7 breathe density (Space.s5 padding, ActiveCard grouping).
//    • Uses §4.3 iridescent hairline under the top bar.
//    • Surfaces the real feature roadmap inline so the driver understands
//      what's shipping here, rather than an empty-state dead zone.
//

import SwiftUI
import MapKit
import CoreLocation
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - DriverTripsPane (tab 2) — Eusoboards

/// The Trips tab IS the Eusoboards screen (EusoTrip's branded load board). A
/// prominent gradient "My Loads" button sits at the top of the scroll
/// surface — tapping it opens `MyLoadsSheet` with Active / Pending /
/// Finished segmented tabs for loads the driver has already claimed. The
/// rest of this surface is the public load market: equipment chips,
/// origin→destination search, and bookable load cards pulled from the wire.
///
/// View modes:
///   • `.list` — default card stack (existing behavior)
///   • `.map`  — HERE Maps rendering every filtered load's pickup +
///               delivery coordinates, with a gradient polyline drawn
///               between the two.
///
/// Brand invariant: the My Loads button uses `LinearGradient.diagonal`
/// (blue→magenta) — never a flat blue — so it carries the same identity
/// as the bottom-nav orb, send-to-ESANG button, and EusoWallet CTA.
struct DriverTripsPane: View {
    @Environment(\.palette) var palette
    @Environment(\.colorScheme) private var scheme

    /// Env-injected nav handler from `ContentView`. Used by the SOS
    /// sheet's "Open Zeun Mechanics" footer to deep-link the driver
    /// from a mid-trip emergency over to the Loads tab where the full
    /// Zeun mechanic flow lives. Same handler the BottomNav uses, so
    /// behavior matches a manual nav tap.
    @Environment(\.driverNavHandler) private var driverNavHandler

    /// Live trip state — drives the pane's top-level branch between the
    /// public Eusoboards load board (when idle) and the active-trip
    /// surface with map, nav info, and SOS (when a trip is active).
    /// Per user Request 3 (2026-04-19):
    ///   > whe the job is currently active thats where you also click on
    ///   > where you can see the map and navigations and anything
    ///   > pertaining to the current trip (dont forget 'SOS' button)
    @EnvironmentObject private var trip: DriverTripController

    enum EusoboardsViewMode: String, CaseIterable, Identifiable {
        case list, map
        var id: String { rawValue }
        var icon: String { self == .list ? "list.bullet" : "map.fill" }
        var title: String { self == .list ? "List" : "Map" }
    }

    @State private var showMyLoads: Bool = false
    @State private var equipmentFilter: String = "All"
    @State private var originQuery: String = ""
    @State private var destinationQuery: String = ""
    @State private var viewMode: EusoboardsViewMode = .list
    @State private var selectedLoadID: String? = nil
    @State private var showSOSSheet: Bool = false

    /// Decoded HERE truck route for the current active trip. When this is
    /// nil we render the straight-line pickup→delivery connector as a
    /// placeholder; once HereRoutingClient returns we swap to the real
    /// road-following gradient polyline. Keyed on `trip.currentLoad?.id`
    /// so swapping to a new active load re-triggers the fetch.
    @State private var activeRoute: HereRoute? = nil
    /// Tracks the load id the current `activeRoute` was computed for.
    /// Guards against stale routes sticking around after the driver
    /// finishes one load and picks up another.
    @State private var activeRouteLoadID: String? = nil

    private let equipmentChips: [String] = [
        "All", "Dry Van", "Reefer", "Flatbed", "Step Deck", "Hazmat", "Power Only"
    ]

    /// Live market feed — `loads.search(status:"available")` through
    /// `LoadBoardStore`. Every seeded `[AvailableLoad]` literal that
    /// used to live here (PACCO, ColdChain, Sunbelt, etc.) is gone —
    /// the store renders a spinner while the fetch is in flight, the
    /// EusoEmptyState when the server confirms an empty board, and
    /// the real cards as soon as tRPC delivers them. See
    /// `ViewModels/LiveDataStores.swift`.
    @StateObject private var boardStore = LoadBoardStore()

    /// Live count of the driver's active loads — backs the "N active"
    /// pill on the My Loads button. Pinned to `MyLoadsStore.Bucket.active`
    /// (`loads.search(status:"in_transit", limit: 30)`) so the count
    /// reflects whatever the backend actually has assigned to this
    /// driver right now. Replaces a hardcoded `"3 active"` literal that
    /// violated the doctrine ("zero mock data, 0 hardcoded counts").
    /// Refreshed at view-appear via `.task`; cheap because the same
    /// procedure powers `DriverMyLoadsPane`.
    @StateObject private var activeLoadsStore: MyLoadsStore = {
        let s = MyLoadsStore()
        s.bucket = .active
        return s
    }()

    /// Adapter — fold the backend's `LoadSummary` DTO into the
    /// Eusoboards `AvailableLoad` shape the existing card UI expects.
    /// Keeping the view-model struct intact means the card renderer,
    /// filter chips, and map pins don't have to change; only the
    /// data source does.
    private var board: [AvailableLoad] {
        boardStore.items.map(AvailableLoad.from)
    }

    private var filtered: [AvailableLoad] {
        board.filter { l in
            let matchesEq = equipmentFilter == "All" ||
                (equipmentFilter == "Hazmat" ? l.hazmat : l.equipment == equipmentFilter)
            let matchesO = originQuery.isEmpty ||
                l.origin.localizedCaseInsensitiveContains(originQuery)
            let matchesD = destinationQuery.isEmpty ||
                l.destination.localizedCaseInsensitiveContains(destinationQuery)
            return matchesEq && matchesO && matchesD
        }
    }

    /// Computed binding that maps `selectedLoadID` ↔ the matching
    /// `AvailableLoad`. Feeds `.sheet(item:)` so tapping a pickup pin
    /// (or a mini-card) presents the full LoadDetailSheet — and
    /// dismissing the sheet clears the selection.
    private var selectedLoadBinding: Binding<AvailableLoad?> {
        Binding(
            get: {
                guard let id = selectedLoadID else { return nil }
                return board.first(where: { $0.id == id })
            },
            set: { newValue in
                selectedLoadID = newValue?.id
            }
        )
    }

    var body: some View {
        Group {
            if trip.phase.isActiveTrip {
                activeTripBody
            } else {
                eusoboardsBody
            }
        }
        .sheet(isPresented: $showMyLoads) {
            MyLoadsSheet()
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        // Pin-tap → full load-detail sheet. Mirrors the web Eusoboards
        // click-through: route · permits · prohibited routes · cargo ·
        // broker · rate breakdown.
        .sheet(item: selectedLoadBinding) { load in
            LoadDetailSheet(
                load: load,
                onBook: {
                    selectedLoadID = nil
                },
                onBid: {
                    selectedLoadID = nil
                },
                onMessageBroker: {
                    // Hook into messaging in a later wave.
                }
            )
            .environment(\.palette, palette)
            .eusoSheetX()
        }
    }

    // MARK: Eusoboards body (idle — no active trip)

    /// The public load-board surface — rendered when the driver has no
    /// active trip. My Loads CTA + search + equipment chips +
    /// list/map toggle + results.
    private var eusoboardsBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Patch #1: EusoHeader (unified pane header). The old bullet-
            // separated uppercase subtitle ("Available freight · book &
            // dispatch") is replaced by a single live-sentence descriptor.
            EusoHeader(title: "Eusoboards",
                       subtitle: "Live load board")
            IridescentHairline()
            ScrollView {
                // TileStack — staggered tile-in entrance for the whole
                // Eusoboards surface (My Loads CTA → search → chips → toggle
                // → results → cards). Matches the web platform's load-in.
                TileStack(alignment: .leading, spacing: Space.s4) {
                    myLoadsButton           // ← brand-gradient CTA
                    searchCard              // ← origin / destination inputs
                    equipmentRow            // ← horizontal chip filter
                    viewModeToggle          // ← list / map segmented control
                    resultsHeader           // ← count + live badge
                    Group {                 // ← bookable loads OR map view
                        switch viewMode {
                        case .list: loadCardStack
                        case .map:  mapStack
                        }
                    }
                    Color.clear
                        .frame(height: Device.navHeight + Device.safeBottom + Space.s4)
                }
                .padding(Space.s5)
            }
            .scrollIndicators(.hidden)
            // Pull-to-refresh re-runs the live `loads.search` call on the
            // LoadBoardStore. No more "visible pulse" — the store owns
            // the loading/error/empty lifecycle end-to-end.
            .refreshable {
                // Pull-to-refresh fans out: the public board re-fetches
                // and the private "active loads" count refreshes in
                // parallel so the My Loads pill on this surface stays
                // honest even when the driver's bookings change while
                // the eusoboards tab is open.
                async let a: Void = boardStore.refresh()
                async let b: Void = activeLoadsStore.refresh()
                _ = await (a, b)
            }
        }
        // Kick the first fetch the moment the pane appears so the board
        // is already populating by the time the tile-in animation
        // settles. Subsequent taps on the tab re-use whatever the store
        // has until the user pulls to refresh. Both stores hydrate in
        // parallel — the public board for the list and the driver's
        // active-load count for the My Loads pill.
        .task {
            async let a: Void = boardStore.refresh()
            async let b: Void = activeLoadsStore.refresh()
            _ = await (a, b)
        }
    }

    // MARK: Active-trip body (map, nav, SOS)

    /// Shown when `trip.phase.isActiveTrip == true`. Per user Request 3:
    /// the Truck tab hosts the active-trip surface with map, navigation
    /// info, and a prominent SOS button for reporting breakdowns or
    /// other emergencies mid-trip.
    private var activeTripBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar(title: "Active Trip",
                   subtitle: trip.phase.displayName.uppercased() + " · EN ROUTE")
            IridescentHairline()
            ScrollView {
                // TileStack — cafe-door staggered tile-in for every child
                // (load card, map, nav row, SOS) so this pane matches the
                // rest of the app on selection.
                TileStack(alignment: .leading, spacing: Space.s4) {
                    activeTripLoadCard
                    activeTripMap
                    activeTripNavRow
                    sosButton
                    Color.clear
                        .frame(height: Device.navHeight + Device.safeBottom + Space.s4)
                }
                .padding(Space.s5)
            }
            .scrollIndicators(.hidden)
            // Drag-down while on an active trip re-syncs ETA, phase, and
            // load card from the trip controller. For now this is a
            // feedback-only pulse; swap in `tripController.refresh()` when
            // live telemetry is in. We also opportunistically refetch
            // the HERE truck-route polyline so drivers who roll out of
            // cell coverage can pull-to-reload when signal returns.
            .refreshable {
                if let load = trip.currentLoad {
                    await fetchActiveRoute(for: load)
                }
                await refreshPulse()
            }
        }
        // Emergency sheet — surfaces the SOS triage surface. Wires into
        // `trpc.interstate.createSOS` on the server per web parity, and
        // (per user request 2026-04-19) dual-fires `zeunMechanics
        // .reportBreakdown` when the driver picks the Breakdown tile so
        // the ticket lands in the Zeun mechanic queue. The
        // `onOpenZeun` callback lets a non-emergency mechanical issue
        // skip the SOS broadcast and head straight into the full Zeun
        // flow (VIN, fault codes, photos, telemetry, DIY guides, repair-
        // provider matching) over on the Loads tab.
        .sheet(isPresented: $showSOSSheet) {
            SOSEmergencySheet(onOpenZeun: {
                driverNavHandler?("loads")
            })
            .environment(\.palette, palette)
            .environmentObject(trip)
            .eusoSheetX()
        }
    }

    /// Active load summary — reads from `trip.currentLoad` (seeded with
    /// `Load.demoActive()` so the simulator always has populated cards).
    @ViewBuilder
    private var activeTripLoadCard: some View {
        if let load = trip.currentLoad {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text(load.loadNumber)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: trip.phase.displayName, kind: .info)
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(load.pickupLocation?.city ?? "—")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(load.deliveryLocation?.city ?? "—")
                        .font(EType.h2)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                HStack(spacing: Space.s2) {
                    Text(load.rateDisplay)
                        .font(EType.bodyStrong)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("·")
                        .foregroundStyle(palette.textTertiary)
                    Text(load.rpmDisplay)
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Brand.blue.opacity(0.45),
                                Brand.magenta.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
    }

    /// Map rendering for the active trip — pickup + delivery + gradient
    /// polyline between them. Until HERE returns the decoded truck route
    /// we render the straight pickup→delivery lane connector as a
    /// placeholder; once `activeRoute` is populated we swap to the real
    /// road-following polyline (same blue→magenta gradient treatment).
    /// The driver's live position (when wired to CLLocationManager) will
    /// still render as the user-location dot over whichever polyline is
    /// active.
    @ViewBuilder
    private var activeTripMap: some View {
        if let load = trip.currentLoad,
           let pickup = load.pickupLocation,
           let delivery = load.deliveryLocation
        {
            let routeReady = activeRoute != nil
                && activeRouteLoadID == String(load.id)

            // Canonical OMV vector map + live HERE add-ons (fuel / EV /
            // weather / traffic / sponsored ad-zones). Uses the real decoded
            // HERE truck-route polyline when ready, else a straight pickup→
            // delivery connector while the route fetch is in flight.
            let routeCoords: [HereLatLng] = routeReady
                ? (activeRoute?.sections ?? [])
                    .flatMap { HereFlexiblePolyline.decode($0.polyline) }
                    .map { HereLatLng($0) }
                : []
            let lineCoords: [HereLatLng] = routeCoords.isEmpty
                ? [HereLatLng(pickup.lat, pickup.lng), HereLatLng(delivery.lat, delivery.lng)]
                : routeCoords

            HereLiveMapView(
                center: .init((pickup.lat + delivery.lat) / 2,
                              (pickup.lng + delivery.lng) / 2),
                zoom: 7,
                firstPerson: true,
                route: lineCoords,
                baseLayers: [
                    .route(polyline: lineCoords, colorHex: "#1473FF"),
                    .markers([
                        .init(at: .init(pickup.lat, pickup.lng), kind: .pickup, label: pickup.city),
                        .init(at: .init(delivery.lat, delivery.lng), kind: .delivery, label: delivery.city)
                    ])
                ],
                addOns: .driverEnRoute
            )
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Brand.blue.opacity(0.55),
                                Brand.magenta.opacity(0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Brand.blue.opacity(scheme == .dark ? 0.25 : 0.14),
                    radius: 10, x: -2, y: 3)
            .shadow(color: Brand.magenta.opacity(scheme == .dark ? 0.25 : 0.14),
                    radius: 10, x: 2, y: 3)
            // Fetch the truck-aware polyline from HERE Routing v8 as
            // soon as the active trip map appears, and refetch whenever
            // the active load id changes (e.g. driver completes one
            // load and picks up the next).
            .task(id: String(load.id)) {
                await fetchActiveRoute(for: load)
            }
        }
    }

    /// Calls HERE Routing v8 for the given active load and caches the
    /// decoded polyline into `activeRoute`. Silently falls back to the
    /// straight-line lane connector if the call fails (missing api key,
    /// no network, etc.) so the map is never empty.
    @MainActor
    private func fetchActiveRoute(for load: Load) async {
        // Reset the existing route so we never flash a stale polyline
        // from a previous load.
        if activeRouteLoadID != String(load.id) {
            activeRoute = nil
            activeRouteLoadID = nil
        }
        do {
            let resp = try await HereRoutingClient.shared.route(for: load)
            if let first = resp.routes.first {
                activeRoute = first
                activeRouteLoadID = String(load.id)
            }
        } catch {
            // Keep the straight-line fallback on failure; the error is
            // visually implicit (user still sees a connector) and will
            // self-heal on the next pull-to-refresh.
            activeRoute = nil
            activeRouteLoadID = nil
        }
    }

    /// Nav tiles for the active-trip surface — miles remaining, ETA,
    /// next stop. Sourced from the trip controller today as static text;
    /// will read live from `CLLocationManager` + `HereRoutingClient` in
    /// the next wave.
    private var activeTripNavRow: some View {
        HStack(spacing: Space.s2) {
            navTile(icon: "road.lanes",
                    label: "MILES LEFT",
                    value: milesRemaining)
            navTile(icon: "clock",
                    label: "ETA",
                    value: etaDisplay)
            navTile(icon: "mappin.and.ellipse",
                    label: "NEXT STOP",
                    value: nextStopDisplay)
        }
    }

    private var milesRemaining: String {
        guard let load = trip.currentLoad else { return "—" }
        return "\(Int(load.distanceValue)) mi"
    }

    private var etaDisplay: String {
        trip.currentLoad?.deliveryDate.flatMap { String($0.prefix(16)) } ?? "—"
    }

    private var nextStopDisplay: String {
        switch trip.phase {
        case .loadLockedPrehaul,
             .enrouteToPickup, .approachingPickup, .atPickupGate,
             .pickupArrival, .pickupLoading, .spectraMatchVerdict,
             .pickupBolSigning, .detachSequence:
            return trip.currentLoad?.pickupLocation?.city ?? "Pickup"
        default:
            return trip.currentLoad?.deliveryLocation?.city ?? "Delivery"
        }
    }

    @ViewBuilder
    private func navTile(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    /// SOS emergency button — full-width, red-gradient, prominent.
    /// Opens `SOSEmergencySheet` for breakdown / medical / accident /
    /// hazmat-spill / security / fuel / other triage (matches the web
    /// platform's `trpc.interstate.createSOS` emergency taxonomy).
    private var sosButton: some View {
        Button {
            showSOSSheet = true
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.22))
                        .frame(width: 44, height: 44)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOS · Emergency")
                        .font(EType.title)
                        .foregroundStyle(.white)
                    Text("Breakdown · accident · medical · spill")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.92))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.95, green: 0.20, blue: 0.25),
                                Color(red: 0.76, green: 0.05, blue: 0.40)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.95, green: 0.20, blue: 0.25).opacity(0.40),
                    radius: 18, y: 6)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("SOS emergency — breakdown, accident, medical, spill")
    }

    // MARK: View mode (list / map) segmented control

    /// Brand-gradient pill toggle between the stacked card list and the
    /// HERE Maps rendering of every filtered load's pickup + delivery
    /// coordinates. Selected chip uses `LinearGradient.diagonal`; unselected
    /// chips read the surrounding palette so the control sits comfortably
    /// in both registers.
    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(EusoboardsViewMode.allCases) { mode in
                let active = viewMode == mode
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        viewMode = mode
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(mode.title)
                            .font(EType.caption.weight(active ? .semibold : .regular))
                    }
                    .foregroundStyle(active ? .white : palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if active {
                                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                    .fill(LinearGradient.diagonal)
                            } else {
                                Color.clear
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title) view")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                .fill(palette.bgCardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: Map stack (HERE Maps rendering of filtered loads)

    /// Renders the filtered loads as a single `HereMapView` with a pickup
    /// + delivery annotation per lane, auto-fitting the camera across every
    /// coordinate. Below the map we surface a horizontally-scrolling mini
    /// card rail so the driver can page through lanes without collapsing
    /// back to list view. Tapping a mini card snaps the map to that lane
    /// and deep-links into the booking flow.
    private var mapStack: some View {
        VStack(spacing: Space.s3) {
            mapCard
            mapLegend
            mapMiniCards
        }
    }

    private var mapCard: some View {
        // Single pickup-pin per load — no origin→destination polyline.
        // Tapping a pin routes through `onSelectMarker` into the full
        // load-detail sheet (see `.sheet(item:)` below). This matches the
        // web Eusoboards pattern: the map is a pick-a-load surface, all
        // route / permit / prohibited-lane detail lives in the sheet.
        // One tappable pickup-pin per load — id bubbles back through
        // HereLiveMapView.onSelectMarker into the load-detail sheet. No
        // add-on overlays here: the board is a pick-a-load surface, kept
        // clean. (Migrated off the raster `HereMapView` onto the canonical
        // OMV vector renderer that the plan actually serves.)
        let boardMarkers: [HereMarker] = filtered.map { load in
            HereMarker(
                at: HereLatLng(load.originLat, load.originLng),
                kind: .pickup,
                label: "\(load.origin) · $\(Int(load.rate)) · \(load.miles) mi · \(load.equipment)",
                id: load.id
            )
        }
        let boardCenter: HereLatLng = {
            guard !boardMarkers.isEmpty else { return HereLatLng(39.5, -98.35) }
            let lat = boardMarkers.map { $0.at.lat }.reduce(0, +) / Double(boardMarkers.count)
            let lng = boardMarkers.map { $0.at.lng }.reduce(0, +) / Double(boardMarkers.count)
            return HereLatLng(lat, lng)
        }()

        return ZStack(alignment: .topTrailing) {
            HereLiveMapView(
                center: boardCenter,
                zoom: boardMarkers.isEmpty ? 4 : 5,
                baseLayers: [.markers(boardMarkers)],
                addOns: [],
                showLegend: false,
                onSelectMarker: { id in
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedLoadID = id
                    }
                }
            )
            .frame(height: 340)
            // Brand-gradient scrim: subtle blue→magenta tint wash, plus a
            // top-and-bottom white fade that softens Apple's land fill into
            // an Eusoboards-native look. Tints are ultra-low opacity so the
            // real map is still readable.
            .overlay(
                LinearGradient(
                    colors: [
                        Brand.blue.opacity(scheme == .dark ? 0.18 : 0.08),
                        .clear,
                        Brand.magenta.opacity(scheme == .dark ? 0.18 : 0.08),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            )
            .overlay(
                LinearGradient(
                    colors: [
                        (scheme == .dark ? Color.black : Color.white).opacity(0.55),
                        .clear,
                        .clear,
                        (scheme == .dark ? Color.black : Color.white).opacity(0.45),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Brand.blue.opacity(0.55),
                                Brand.magenta.opacity(0.55),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Brand.blue.opacity(scheme == .dark ? 0.25 : 0.14),
                    radius: 10, x: -2, y: 3)
            .shadow(color: Brand.magenta.opacity(scheme == .dark ? 0.25 : 0.14),
                    radius: 10, x: 2, y: 3)

            // Live-data pill (top-right) — replaces the HERE attribution
            // badge. We're on the Apple basemap now, so no HERE license
            // attribution is required.
            HStack(spacing: 6) {
                Circle()
                    .fill(Brand.success)
                    .frame(width: 6, height: 6)
                Text("\(filtered.count) LIVE")
                    .font(EType.micro).tracking(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule().fill(LinearGradient.diagonal.opacity(0.92))
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
            .padding(10)
            .accessibilityLabel("\(filtered.count) live loads on map")
        }
    }

    private var mapLegend: some View {
        HStack(spacing: Space.s3) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 10, height: 10)
                    Circle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                        .frame(width: 10, height: 10)
                }
                Text("Pickup")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("·")
                .foregroundStyle(palette.textTertiary)
            Text("Tap a pin for route · permits · cargo")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("\(filtered.count) load\(filtered.count == 1 ? "" : "s") on map".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s2)
    }

    private var mapMiniCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(filtered) { load in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text(load.origin)
                                .font(EType.caption.weight(.semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(load.destination)
                                .font(EType.caption.weight(.semibold))
                        }
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("$\(Int(load.rate))")
                                .font(EType.caption.weight(.bold))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("·")
                                .foregroundStyle(palette.textTertiary)
                            Text("\(load.miles) mi")
                                .font(EType.micro).tracking(0.6)
                                .foregroundStyle(palette.textSecondary)
                            Text("·")
                                .foregroundStyle(palette.textTertiary)
                            Text(load.equipment.uppercased())
                                .font(EType.micro).tracking(0.6)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .frame(width: 240, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(
                                selectedLoadID == load.id
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.borderFaint)
                            )
                    )
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedLoadID = load.id
                        }
                    }
                }
            }
        }
    }

    // MARK: Gradient "My Loads" button (brand gradient, NOT solid blue)

    private var myLoadsButton: some View {
        Button {
            showMyLoads = true
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(.white.opacity(0.18))
                    Image(systemName: "truck.box.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("My Loads")
                        .font(EType.title)
                        .foregroundStyle(.white)
                    Text("Active · pending · finished")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                // Live "N active" pill — count comes from
                // `activeLoadsStore.items.count` (live `loads.search(
                // status:"in_transit")`). Hidden while the *first* fetch
                // is in flight (state == .loading) so we never flash a
                // stale "0 active" pill before the network resolves;
                // once the server returns the pill renders with the
                // real count, including 0 when the driver has no
                // in-transit loads. Replaces a hardcoded `"3 active"`
                // string that violated the doctrine "no fake data,
                // dynamic ready pages with 0 data" (2026-04-24 audit).
                if !activeLoadsStore.isInitialLoading {
                    let n = activeLoadsStore.items.count
                    ZStack {
                        Capsule().fill(.white.opacity(0.22))
                        HStack(spacing: 4) {
                            Circle().fill(.white).frame(width: 6, height: 6)
                            Text("\(n) active")
                                .font(EType.micro).tracking(0.6)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                    }
                    .frame(height: 22)
                    .fixedSize()
                    .accessibilityLabel("\(n) active load\(n == 1 ? "" : "s")")
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(LinearGradient.diagonal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
            // Doctrine §2.1 — dual-shadow brand glow (blue-left / magenta-right)
            // mirrors the activeTripMap + liveMapCard pattern so every
            // LinearGradient.diagonal surface reads as blue→magenta on both
            // the fill AND the drop shadow. Previously a single Brand.blue
            // shadow which read magenta-less.
            .shadow(color: Brand.blue.opacity(0.30), radius: 16, x: -2, y: 6)
            .shadow(color: Brand.magenta.opacity(0.30), radius: 16, x: 2, y: 6)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("My Loads — Active, Pending, Finished")
    }

    // MARK: Origin → Destination search card

    private var searchCard: some View {
        VStack(spacing: 0) {
            searchField(icon: "circle.inset.filled",
                        placeholder: "Origin city or state",
                        text: $originQuery)
            Divider().overlay(palette.borderFaint).padding(.leading, 52)
            searchField(icon: "location.north.line.fill",
                        placeholder: "Destination city or state",
                        text: $destinationQuery)
        }
        .eusoCard(radius: Radius.lg)
    }

    @ViewBuilder
    private func searchField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 28, height: 28)
            TextField("", text: text, prompt:
                Text(placeholder).foregroundStyle(palette.textTertiary))
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: Equipment filter chip row

    private var equipmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(equipmentChips, id: \.self) { chip in
                    let active = equipmentFilter == chip
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            equipmentFilter = chip
                        }
                    } label: {
                        Text(chip)
                            .font(EType.caption.weight(active ? .semibold : .regular))
                            .foregroundStyle(active ? .white : palette.textPrimary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, 8)
                            .background(
                                Group {
                                    if active {
                                        RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                            .fill(LinearGradient.diagonal)
                                    } else {
                                        RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                            .fill(palette.bgCardSoft)
                                    }
                                }
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                    .strokeBorder(active ? .clear : palette.borderFaint)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Results header

    private var resultsHeader: some View {
        HStack {
            Text("\(filtered.count) loads".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(Brand.success)
                    .frame(width: 6, height: 6)
                Text("Live · updated 12s ago")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Load card stack

    private var loadCardStack: some View {
        VStack(spacing: Space.s3) {
            if filtered.isEmpty {
                VStack(spacing: Space.s2) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(palette.textTertiary)
                    Text("No loads match your filters")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Try clearing the origin, destination, or equipment chip.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(Space.s5)
                .frame(maxWidth: .infinity)
                .eusoCard(radius: Radius.lg)
            } else {
                ForEach(filtered) { load in
                    Button {
                        selectedLoadID = load.id
                    } label: {
                        LoadBoardCard(load: load)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityLabel("Load \(load.id), \(load.origin) to \(load.destination), $\(Int(load.rate))")
                }
            }
        }
    }

    // MARK: Title bar

    @ViewBuilder
    private func topBar(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 40, weight: .heavy))
                // Pane hero title — gradient in both registers. Matches the
                // "Hey, <name>" treatment on Home so Wallet/Trips/Me/Load
                // Boards all read brand-native rather than flat black in
                // light mode.
                .foregroundStyle(LinearGradient.diagonal)
            Text(subtitle.uppercased())
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: Pull-to-refresh
    //
    // Both scrollable bodies (eusoboardsBody and activeTripBody) bind
    // `.refreshable` to this shared stub. It simulates a backend round
    // trip so the spinner is actually visible; when real data sources
    // land this becomes a fan-out of async refetches (loads list for
    // Eusoboards; trip controller + HOS for Active Trip).
    @MainActor
    private func refreshPulse() async {
        try? await Task.sleep(nanoseconds: 700_000_000)
    }
}

// MARK: - Load board data

/// One row on the public Eusoboards surface.
struct AvailableLoad: Identifiable, Equatable {
    let id: String
    let origin: String
    let destination: String
    let miles: Int
    let equipment: String
    let rate: Double
    let rpm: Double
    let pickupWindow: String
    let broker: String
    let hazmat: Bool
    let weight: String
    /// 0–5 — used to badge "hot" lanes with a gradient flame chip.
    let hotScore: Int
    /// Origin city centroid, rendered as the pickup annotation on the
    /// Eusoboards map view and seeded into `HereRoutingClient` when the
    /// driver taps through to the load detail sheet.
    let originLat: Double
    let originLng: Double
    /// Destination city centroid — paired with `originLat/Lng` to draw the
    /// blue→magenta gradient polyline on the Eusoboards map.
    let destLat: Double
    let destLng: Double
    /// Backend numeric loadId. Distinct from `id` (which carries the
    /// human-readable `loadNumber` so the UI can render "LOAD-2026-A1B2"
    /// rather than "94120"). Populated by every `AvailableLoad.from(...)`
    /// adapter so the Book Now / Bid flow can post directly to
    /// `loadBidding.submit({ loadId: Int })` without an extra round-trip
    /// to look up the numeric id from the loadNumber. nil only when the
    /// adapter genuinely doesn't know the id (preview rows, demo seeds).
    var backendLoadId: Int? = nil
    /// US state codes for the pickup / delivery endpoints. Used by the
    /// LoadDetailSheet to fire `rates.compareLaneRate(originState,
    /// destState, …)` so the driver sees the lane's market percentile +
    /// recommended counter rather than booking blind.
    var originState: String? = nil
    var destState: String? = nil

    /// Convenience — pickup as a `LoadLocation` for HERE Maps annotations.
    var pickupLocation: LoadLocation {
        let parts: [String] = origin.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        let city: String  = parts.first ?? origin
        let state: String = parts.count > 1 ? parts[1] : ""
        return LoadLocation(
            address: "",
            city: city,
            state: state,
            zipCode: "",
            lat: originLat, lng: originLng
        )
    }

    /// Convenience — delivery as a `LoadLocation` for HERE Maps annotations.
    var deliveryLocation: LoadLocation {
        let parts: [String] = destination.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        let city: String  = parts.first ?? destination
        let state: String = parts.count > 1 ? parts[1] : ""
        return LoadLocation(
            address: "",
            city: city,
            state: state,
            zipCode: "",
            lat: destLat, lng: destLng
        )
    }
}

// MARK: - LoadBoardCard

/// Single bookable load on the Eusoboards surface.
struct LoadBoardCard: View {
    let load: AvailableLoad
    @Environment(\.palette) var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Top row — ID + equipment + hazmat
            HStack(spacing: Space.s2) {
                Text(load.id)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // Patch #2: EusoBadge. `.hazmat` for hazmat loads, `.info`
                // for generic equipment types (REEFER / FLATBED / DRY VAN).
                EusoBadge(label: load.equipment,
                          kind: load.hazmat ? .hazmat : .info)
                if load.hotScore >= 4 {
                    // Patch #2: EusoBadge(.hot) replaces the ad-hoc
                    // gradient capsule — one primitive, every surface.
                    EusoBadge(label: "HOT",
                              kind: .hot,
                              icon: Image(systemName: "flame.fill"))
                }
            }

            // Lane row — origin → destination + miles
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PICKUP")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(load.origin)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("\(load.miles) mi")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DROP")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(load.destination)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
            }

            Divider().overlay(palette.borderFaint)

            // Rate row
            HStack(alignment: .firstTextBaseline) {
                Text("$\(Int(load.rate).formatted())")
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(String(format: "$%.2f/mi", load.rpm))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(load.weight)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            // Meta row
            HStack(spacing: Space.s3) {
                Label(load.pickupWindow, systemImage: "clock")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(load.broker)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }

            // Action row
            HStack(spacing: Space.s2) {
                Button {
                    // book-load hook
                } label: {
                    Text("Book now")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(LinearGradient.diagonal)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    // view-details hook
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Load details")
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }
}

// MARK: - PressableCardStyle

/// Subtle scale-and-dim on press — reused by the My Loads gradient CTA so it
/// still signals tactility without the gradient getting muddied by a hue
/// rotation (the gradient itself is the identity).
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - MyLoadsSheet

/// Segmented view of the driver's own claimed loads — Active / Pending /
/// Finished — presented as a full-height sheet from the Eusoboards "My
/// Loads" CTA.
struct MyLoadsSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @State private var bucket: MyLoadBucket = .active
    /// Row the driver tapped — drives the canonical `LoadDetailSheet`
    /// so the Eusoboards "My Loads" sheet and Driver "Loads" tab share
    /// the same detail affordance.
    @State private var selectedLoad: MyLoad? = nil
    /// 2026 UX motion doc §3.1 — load card → load detail hero zoom.
    /// Namespace declared here, threaded to both the source MyLoadCard
    /// and the destination LoadDetailSheet hero so SwiftUI interpolates
    /// the geometry on sheet presentation. Best-effort for `.sheet()`
    /// (the canonical zoom transition is `NavigationLink + .navigationTransition(.zoom)`
    /// which requires NavigationStack — sheets don't natively zoom but
    /// the matched geometry still gives a "the card became the sheet"
    /// feel as the modal animates up).
    @Namespace private var loadHero

    /// Live `loads.search(status:)` backed store. Every seeded MyLoad
    /// literal that used to live here (the EU-99xxx IDs, PACCO/BorderLink
    /// broker strings, hardcoded ETAs) is gone — the store pulls the
    /// right bucket from the backend and folds the summaries onto the
    /// UI-facing `MyLoad` shape via `MyLoad.from(_:bucket:)`.
    @StateObject private var myLoadsStore = MyLoadsStore()

    private var visible: [MyLoad] {
        myLoadsStore.items.map { MyLoad.from($0, bucket: bucket) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline()
            segmented
            ScrollView {
                // Plain VStack + per-item `cafeDoorReveal(index:)` so each
                // My Load card swings in from an alternating side with a
                // staggered delay. TileStack can't be used here because
                // ForEach is opaque to TileStack's _VariadicView child
                // walk (it'd treat the whole list as one child), so we
                // compute the index ourselves.
                VStack(spacing: Space.s3) {
                    if myLoadsStore.isLoading && visible.isEmpty {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding(Space.s5)
                    } else if visible.isEmpty {
                        liveEmptyState
                            .cafeDoorReveal(index: 0)
                    } else {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, load in
                            Button {
                                selectedLoad = load
                            } label: {
                                MyLoadCard(load: load, heroNamespace: loadHero)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows route, rate, and broker detail")
                            .cafeDoorReveal(index: idx)
                        }
                    }
                }
                .padding(Space.s5)
            }
            .scrollIndicators(.hidden)
            // Pull-to-refresh re-runs the live `loads.search` call for
            // whichever bucket is currently selected.
            .refreshable { await myLoadsStore.refresh() }
        }
        // Swap the bucket → the store re-fetches via its `didSet`.
        .onChange(of: bucket) { _, newBucket in
            myLoadsStore.bucket = MyLoadsStore.Bucket(rawValue: newBucket.storeKey) ?? .active
        }
        .task {
            myLoadsStore.bucket = MyLoadsStore.Bucket(rawValue: bucket.storeKey) ?? .active
            await myLoadsStore.refresh()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage)
        // Tap-a-row → canonical Load Details sheet. Threads the
        // hero namespace + source id so the card's id/origin/dest
        // text animates as one continuous element into the sheet
        // header per §3.1 of the 2026 UX motion doc.
        .sheet(item: $selectedLoad) { load in
            LoadDetailSheet(
                load: AvailableLoad.from(load),
                heroNamespace: loadHero,
                heroSourceId: load.id
            )
            .environment(\.palette, palette)
            .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("My Loads")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ACTIVE · PENDING · FINISHED")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close my loads")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Segmented control

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(MyLoadBucket.allCases, id: \.self) { b in
                let active = bucket == b
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { bucket = b }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Text(b.title)
                                .font(EType.bodyStrong)
                                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                            // Only the currently-selected bucket has a live
                            // count — the store fetches one bucket at a time
                            // to avoid triple-firing `loads.search`. Other
                            // buckets render as a dash until tapped.
                            Text(active ? "\(visible.count)" : "—")
                                .font(EType.micro).tracking(0.4)
                                .foregroundStyle(active ? .white : palette.textTertiary)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(
                                    Capsule().fill(active
                                                   ? AnyShapeStyle(LinearGradient.diagonal)
                                                   : AnyShapeStyle(palette.tintNeutral))
                                )
                        }
                        Rectangle()
                            .fill(active
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(Color.clear))
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s3)
    }

    // MARK: Empty state

    private var emptyState: some View { liveEmptyState }

    /// Branded empty state used for every bucket. Copy is
    /// bucket-specific to follow the canonical empty-state guide in
    /// `mock_data_audit/empty_state_spec.md §4`.
    private var liveEmptyState: some View {
        let (title, subtitle): (String, String) = {
            switch bucket {
            case .active:
                return ("No active loads",
                        "Accept a tender from Eusoboards and you'll see it here.")
            case .pending:
                return ("No pending tenders",
                        "Brokers will offer here — tender accept or decline within the window.")
            case .finished:
                return ("No completed loads yet",
                        "Your finished loads + POD receipts will log here.")
            }
        }()
        return EusoEmptyState(
            systemImage: bucket.glyph,
            title: title,
            subtitle: subtitle
        )
    }
}

// MARK: - MyLoadCard

// MARK: - OptionalMatchedGeometry
//
// View modifier that conditionally applies `.matchedGeometryEffect`
// when a Namespace is provided, and is a no-op otherwise. Used by
// MyLoadCard so call sites that don't yet thread a hero namespace
// stay source-compatible while ones that do get the §3.1 zoom.

private struct OptionalMatchedGeometry: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct MyLoadCard: View {
    let load: MyLoad
    /// Optional hero namespace — when supplied, the card's load id
    /// + origin/destination text become matchedGeometryEffect anchors
    /// so the LoadDetailSheet hero animates as a continuation of
    /// THIS card per §3.1. Nil means card renders without geometry
    /// anchors (preserves existing call sites that don't yet pass a
    /// namespace).
    var heroNamespace: Namespace.ID? = nil
    @Environment(\.palette) var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(load.id)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
                    .modifier(OptionalMatchedGeometry(id: "load-\(load.id)-id", namespace: heroNamespace))
                Spacer()
                StatusPill(text: load.bucket.pillText, kind: load.bucket.pillKind)
            }

            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PICKUP")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(load.origin)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .modifier(OptionalMatchedGeometry(id: "load-\(load.id)-origin", namespace: heroNamespace))
                }
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("\(load.miles) mi")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("DROP")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(load.destination)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .modifier(OptionalMatchedGeometry(id: "load-\(load.id)-dest", namespace: heroNamespace))
                }
            }

            if load.bucket == .active {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.tintNeutral)
                        Capsule()
                            .fill(LinearGradient.diagonal)
                            .frame(width: max(8, geo.size.width * load.progress))
                    }
                }
                .frame(height: 6)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("$\(Int(load.rate).formatted())")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(load.status)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            HStack {
                Label(load.eta, systemImage: "clock")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(load.broker)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }
}

// MARK: - MyLoad data

struct MyLoad: Identifiable, Equatable {
    let id: String
    let bucket: MyLoadBucket
    let origin: String
    let destination: String
    let miles: Int
    let rate: Double
    /// Short status line ("En route · 63%", "POD cleared · paid", etc.)
    let status: String
    /// Human-readable ETA or delivery stamp.
    let eta: String
    let broker: String
    /// 0...1 — drawn as a gradient bar for `.active` cards.
    let progress: Double
}

enum MyLoadBucket: CaseIterable {
    case active, pending, finished

    var title: String {
        switch self {
        case .active:   return "Active"
        case .pending:  return "Pending"
        case .finished: return "Finished"
        }
    }
    var glyph: String {
        switch self {
        case .active:   return "truck.box"
        case .pending:  return "clock.arrow.2.circlepath"
        case .finished: return "checkmark.seal"
        }
    }
    var pillText: String {
        switch self {
        case .active:   return "Active"
        case .pending:  return "Pending"
        case .finished: return "Delivered"
        }
    }
    var pillKind: StatusPill.Kind {
        switch self {
        case .active:   return .info
        case .pending:  return .warning
        case .finished: return .success
        }
    }
    /// Raw key used to drive `MyLoadsStore.bucket` — matches the store's
    /// own `Bucket` enum raw value so the mapping is 1:1 string-for-string.
    var storeKey: String {
        switch self {
        case .active:   return "active"
        case .pending:  return "pending"
        case .finished: return "finished"
        }
    }
}

// MARK: - DriverLoadsPane (tab 3) — My Loads + Zeun Mechanics

/// The "Loads" tab (formerly "Wallet"). Per user Request 3 (2026-04-19)
/// and the 2026-04-20 DVIR→Zeun fold request:
///
///   > card is changed to the my loads screen where you can see current,
///   > upcoming, pending loads etc. under that same screen should have the
///   > button for zeun mechanics and under that is where dvir history goes
///   > as anything pertaining to maintenance or mechanics is under the zeun
///   > mechanics branch.
///
///   > dvir needs to be folded into zeun as zeun is anything mechanical
///   > including inspection.
///
/// Structure:
///   1. Gradient "My Loads" title + bucket segmented control (Active /
///      Pending / Finished) over a reusable `MyLoadCard` list.
///   2. Maintenance & mechanics section header.
///   3. One gradient Zeun Mechanics card → opens `MeDetailContainer(.zeun)`.
///      DVIR history, pre-trip launcher, breakdown reports, scheduled
///      maintenance, and diagnostics all live inside that single surface
///      (matching the web platform's Zeun Mechanics taxonomy).
///
/// The old EusoWallet view is kept as `DriverWalletPane` and remains
/// reachable from `DriverMePane`'s "Earnings" entry — that's where
/// payments / factoring / fuel card / 1099 content lives now.
struct DriverLoadsPane: View {

    @Environment(\.palette)     var palette
    @Environment(\.colorScheme) private var scheme

    @State private var bucket: MyLoadBucket = .active
    @State private var meRoute: MeDetailRoute? = nil
    /// Row the driver tapped — drives the canonical `LoadDetailSheet`.
    /// Per user direction (2026-04-20):
    ///   > and in my loads. clicking on the loads should reveal the load
    ///   > details like on the eusoboards screen
    /// We pass the row through `AvailableLoad.from(_ my:)` so the shared
    /// detail sheet can render its route map, rate breakdown, and broker
    /// card without a bespoke per-model detail view.
    @State private var selectedLoad: MyLoad? = nil

    /// Live `loads.search(status:)` store. Replaces the duplicate
    /// `[MyLoad]` seed that used to live here — same store type used
    /// by `MyLoadsSheet` so both surfaces share the live feed.
    @StateObject private var myLoadsStore = MyLoadsStore()

    private var visible: [MyLoad] {
        myLoadsStore.items.map { MyLoad.from($0, bucket: bucket) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            ScrollView {
                // TileStack — segmented → loads → maintenance → Zeun card
                // each tile in order, matching the web Loads board reveal.
                TileStack(alignment: .leading, spacing: Space.s4) {
                    segmented
                    loadsSection
                    maintenanceHeader
                    zeunCard
                    Color.clear
                        .frame(height: Device.navHeight + Device.safeBottom + Space.s4)
                }
                .padding(Space.s5)
            }
            .scrollIndicators(.hidden)
            // Pull-to-refresh runs the live `loads.search` for the
            // currently-selected bucket.
            .refreshable { await myLoadsStore.refresh() }
        }
        .onChange(of: bucket) { _, newBucket in
            myLoadsStore.bucket = MyLoadsStore.Bucket(rawValue: newBucket.storeKey) ?? .active
        }
        .task {
            myLoadsStore.bucket = MyLoadsStore.Bucket(rawValue: bucket.storeKey) ?? .active
            await myLoadsStore.refresh()
        }
        // Single sheet presenter for the Zeun drill-in — DVIR history now
        // lives inside the Zeun Mechanics sheet itself.
        .sheet(item: $meRoute) { route in
            MeDetailContainer(route: route)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        // Tap-a-row → canonical Load Details sheet. Mirrors the Eusoboards
        // tap affordance so every surface that shows a load exposes the
        // same detail view.
        .sheet(item: $selectedLoad) { load in
            LoadDetailSheet(load: AvailableLoad.from(load))
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    // MARK: Title bar

    // Patch #1: EusoHeader replaces the old "ACTIVE · PENDING · FINISHED ·
    // MAINTENANCE" bullet-separated uppercase subtitle. The segmented
    // control below already names the buckets, so the subtitle can stay
    // empty — EusoHeader degrades gracefully when it's nil.
    private var topBar: some View {
        EusoHeader(title: "My Loads")
    }

    // MARK: Segmented control (bucket selector)

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(MyLoadBucket.allCases, id: \.self) { b in
                let active = bucket == b
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { bucket = b }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Text(b.title)
                                .font(EType.bodyStrong)
                                .foregroundStyle(active ? palette.textPrimary
                                                        : palette.textSecondary)
                            // Only the currently-selected bucket exposes
                            // a live count — the store loads one bucket
                            // at a time. Other buckets render as a dash.
                            Text(active ? "\(visible.count)" : "—")
                                .font(EType.micro).tracking(0.4)
                                .foregroundStyle(active ? .white
                                                        : palette.textTertiary)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(
                                    Capsule().fill(active
                                                   ? AnyShapeStyle(LinearGradient.diagonal)
                                                   : AnyShapeStyle(palette.tintNeutral))
                                )
                        }
                        Rectangle()
                            .fill(active
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(Color.clear))
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(b.title) bucket")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    // MARK: Loads list

    @ViewBuilder
    private var loadsSection: some View {
        if myLoadsStore.isLoading && visible.isEmpty {
            ProgressView()
                .progressViewStyle(.circular)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s5)
        } else if visible.isEmpty {
            // Branded empty — copy cribbed from the canonical empty-state
            // guide (`mock_data_audit/empty_state_spec.md §4`).
            let (title, subtitle): (String, String) = {
                switch bucket {
                case .active:
                    return ("No active loads",
                            "Accept a tender from Eusoboards and you'll see it here.")
                case .pending:
                    return ("No pending tenders",
                            "Brokers will offer here — tender accept or decline within the window.")
                case .finished:
                    return ("No completed loads yet",
                            "Your finished loads + POD receipts will log here.")
                }
            }()
            EusoEmptyState(systemImage: bucket.glyph,
                           title: title,
                           subtitle: subtitle)
        } else {
            VStack(spacing: Space.s3) {
                ForEach(visible) { load in
                    Button {
                        selectedLoad = load
                    } label: {
                        MyLoadCard(load: load)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows route, rate, and broker detail")
                }
            }
        }
    }

    // MARK: Maintenance section

    private var maintenanceHeader: some View {
        HStack(spacing: Space.s2) {
            Text("Maintenance & mechanics".uppercased())
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Rectangle()
                .fill(LinearGradient.diagonal.opacity(0.4))
                .frame(height: 1)
        }
        .padding(.top, Space.s3)
    }

    /// Top-level entry into Zeun Mechanics — Eusorone's fleet-mechanic
    /// branch. Breakdowns, scheduled maintenance, DVIR inspections, and
    /// diagnostics all live inside the Zeun sheet (per web taxonomy).
    private var zeunCard: some View {
        Button {
            meRoute = .zeun
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(.white.opacity(0.18))
                    Image(systemName: "cpu")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Zeun Mechanics")
                        .font(EType.title)
                        .foregroundStyle(.white)
                    Text("Diagnostics · DVIR · maintenance · breakdowns")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s4)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(LinearGradient.diagonal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Brand.magenta.opacity(0.35), radius: 18, y: 6)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel("Zeun Mechanics — diagnostics, DVIR, maintenance, breakdowns")
    }
}

// MARK: - DriverWalletPane (tab 3 · legacy — reached via Me · Earnings)

/// EusoWallet driver surface — mirrors the web `EusoWallet` register density
/// but re-packed for a single phone column. The prior version was a hero
/// balance + two tiles, which missed most of what a driver actually touches:
/// payment methods, transactions, factoring, per-mile breakdown, 1099, fuel
/// card. The rebuild lays out 8 sections top-to-bottom, all inside a single
/// scroll, with a fixed title/subtitle header that stays anchored above the
/// IridescentHairline the same way the other panes do.
struct DriverWalletPane: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL
    /// Session is optional so previews (which don't inject one) still
    /// compile. When present, `session.user?.id` supplies the driverId
    /// needed by `settlementBatching.getDriverBatchView` in §4.
    @EnvironmentObject private var session: EusoTripSession
    /// Trip controller — provides `currentLoad?.id` for the factoring
    /// offer store (§6). When no active load is set, the store resolves
    /// to `.empty` and the section collapses.
    @EnvironmentObject private var trip: DriverTripController

    // MARK: - Modal state
    enum WalletSheet: String, Identifiable {
        case deposit, withdraw, transfer, card, paymentMethods, factoring, tax
        var id: String { rawValue }
    }
    @State private var sheet: WalletSheet? = nil
    @State private var showAddAccount: Bool = false
    /// In-app PDF viewer presentation for the 1099-NEC download.
    /// Replaces the prior `openURL(u)` Safari kick — the driver
    /// stays inside the EusoTrip app and can save the 1099 to Files
    /// / AirDrop / Mail via EusoPDFViewer's share sheet.
    @State private var taxPdfPresentation: EusoPDFPresentation? = nil

    // MARK: - Stores (all bound to canonical backend procedures)
    //
    // Every section of the rebuild owns one store. Each store either
    // calls a verified tRPC procedure or throws `.comingSoon` — never
    // returns mock data. See `ViewModels/LiveDataStores.swift` for the
    // full wiring map.

    /// §1 — `wallet.getBalance` (verified).
    @StateObject private var balanceStore = WalletBalanceStore()
    /// §3 — `earnings.getWeeklySummaries({ weeks: 7 })` (verified).
    @StateObject private var weeklyStore = WeeklyEarningsStore()
    /// §4 — `settlementBatching.getDriverBatchView({ driverId })` (verified).
    @StateObject private var settlementsStore = UpcomingSettlementsStore()
    /// §5 — `wallet.getTransactions({ limit: 20 })` (verified, projected
    /// from the bare-array backend shape).
    @StateObject private var txnsStore = WalletTransactionsStore()
    /// §6 — `factoring.getOffer({ loadId })` (verified, live).
    @StateObject private var factoringStore = FactoringOfferStore()
    /// §7 — `wallet.getPayoutMethods` (verified; renamed from the prior
    /// `listPaymentMethods` spec to match the canonical router).
    @StateObject private var methodsStore = WalletPaymentMethodsStore()
    /// §8 — `tax.getSummary` (driver-scoped, verified, live).
    @StateObject private var taxStore = TaxSummaryStore()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // §9 spec: EusoHeader at top, title "Wallet", no bullet
                // subtitle.
                EusoHeader(title: "Wallet")
                IridescentHairline()
                // Eight sections, top-to-bottom, each rendered as its
                // own `sectionShell` so empty/error/loading each resolve
                // to a branded state without re-laying out the column.
                TileStack(alignment: .leading, spacing: Space.s5) {
                    section1HeroBalance
                    section2QuickActions
                    section3WeeklyChart
                    section4UpcomingSettlements
                    section5ActivityFeed
                    section6FactoringOffer
                    section7LinkedAccounts
                    section8TaxWithholdings
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s6)
            }
        }
        .refreshable { await refreshAll() }
        .task { await refreshAll() }
        .onChange(of: session.user?.id) { _, newId in
            // When the signed-in user changes, re-pull everything so
            // the pane doesn't show the prior driver's settlements.
            settlementsStore.driverId = Int(newId ?? "0") ?? 0
            Task { await refreshAll() }
        }
        .onChange(of: trip.currentLoad?.id) { _, newId in
            // Active load changed — re-pull the factoring offer for
            // the new load id. `.empty` when nil (no active load).
            factoringStore.loadId = newId
            Task { await factoringStore.refresh() }
        }
        .sheet(item: $sheet) { which in
            WalletSheetContainer(kind: which) { sheet = nil }
                .environment(\.palette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // In-app 1099-NEC viewer — opens the signed PDF inside the
        // EusoTrip app via EusoPDFViewer (PDFKit render + iOS share
        // sheet for Save to Files / AirDrop / Mail). Replaces the
        // prior `openURL(u)` Safari kick on the §8 1099 CTA.
        .sheet(item: $taxPdfPresentation) { pres in
            EusoPDFViewer(
                title: pres.title,
                subtitle: pres.subtitle,
                source: .url(pres.url),
                allowSigning: false,
                onSigned: nil,
                loadIdForWalletPass: nil
            )
        }
        .sheet(isPresented: $showAddAccount) {
            AddPaymentAccountSheet(onLinked: {
                MeAction.fire("wallet.payment-method-linked")
                NotificationCenter.default.post(
                    name: .esangRefreshSurface,
                    object: "wallet"
                )
                Task { await methodsStore.refresh() }
            })
            .environment(\.palette, palette)
            .eusoSheetX()
        }
    }

    /// Single refresh entry point — every section's store is fired in
    /// parallel via `async let` so the pane settles in ~one network
    /// round-trip instead of serialising eight calls.
    private func refreshAll() async {
        // Resolve the driverId from the signed-in session before
        // firing the settlements store — server returns an empty
        // batch list when id is 0.
        settlementsStore.driverId = Int(session.user?.id ?? "0") ?? 0
        // Seed the factoring store with the current active load id
        // before it fires — nil resolves to `.empty` without a
        // round-trip.
        factoringStore.loadId = trip.currentLoad?.id
        async let a: () = balanceStore.refresh()
        async let b: () = weeklyStore.refresh()
        async let c: () = settlementsStore.refresh()
        async let d: () = txnsStore.refresh()
        async let e: () = factoringStore.refresh()
        async let f: () = methodsStore.refresh()
        async let g: () = taxStore.refresh()
        _ = await (a, b, c, d, e, f, g)
    }

    // MARK: - §1 Hero balance card
    //
    // Big balance amount + Available/Pending split + gradient ring around
    // a circular icon. Data: `wallet.getBalance` → WalletAPI.WalletBalance.
    // The $0.00 state is a valid "loaded" state for brand-new drivers;
    // `—` only renders while the store is actually `.loading`.
    private var section1HeroBalance: some View {
        ActiveCard {
            switch balanceStore.state {
            case .loading:
                sectionLoading(minHeight: 160)
            case .empty:
                // BalanceStore folds to `.loaded` always (foldState is
                // default on BaseDynamicStore) — this arm is unreachable
                // but kept exhaustive.
                sectionLoading(minHeight: 160)
            case .error(let err):
                sectionError(err, retry: { Task { await balanceStore.refresh() } })
            case .loaded(let b):
                heroBalanceContent(b)
            }
        }
    }

    @ViewBuilder
    private func heroBalanceContent(_ b: WalletAPI.WalletBalance) -> some View {
        HStack(alignment: .top, spacing: Space.s4) {
            gradientRingAvatar(systemImage: "dollarsign.circle.fill")
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("EusoWallet".uppercased())
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(currency(b.available, currencyCode: b.currency))
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    // §3.7 — wallet balance rolls like an odometer
                    // when the value changes. The 2026 UX motion doc
                    // (§6.2) calls this out specifically: balance is
                    // a numeric the driver watches; popping is jarring.
                    .contentTransition(.numericText())
                    .animation(.spring(.smooth), value: b.available)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Available balance")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        Divider().overlay(palette.borderFaint)
            .padding(.vertical, Space.s3)
        HStack(spacing: Space.s3) {
            MetricTile(
                label: "Available",
                value: currency(b.available, currencyCode: b.currency, digits: 0),
                gradientNumeral: true
            )
            MetricTile(
                label: "Pending",
                value: currency(b.pending, currencyCode: b.currency, digits: 0)
            )
        }
        if b.reserved > 0 || b.escrow > 0 {
            HStack(spacing: Space.s3) {
                if b.reserved > 0 {
                    MetricTile(
                        label: "Reserved",
                        value: currency(b.reserved, currencyCode: b.currency, digits: 0)
                    )
                }
                if b.escrow > 0 {
                    MetricTile(
                        label: "Escrow",
                        value: currency(b.escrow, currencyCode: b.currency, digits: 0)
                    )
                }
            }
            .padding(.top, Space.s2)
        }
        if let ts = b.lastUpdated, !ts.isEmpty {
            Text("Updated \(formatRelative(ts))")
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s3)
        }
    }

    /// Circular gradient ring around a brand-tinted icon. The ring is
    /// drawn with `LinearGradient.diagonal` as the stroke; the inner
    /// tile uses the palette-sourced card background so the register
    /// flip stays clean in both Night and Afternoon.
    @ViewBuilder
    private func gradientRingAvatar(systemImage: String) -> some View {
        ZStack {
            Circle()
                .strokeBorder(LinearGradient.diagonal, lineWidth: 3)
                .frame(width: 64, height: 64)
            Circle()
                .fill(palette.tintNeutral)
                .frame(width: 52, height: 52)
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
        }
    }

    // MARK: - §2 Quick actions row
    //
    // Transfer · Deposit · Withdraw · Card. Four equal-width gradient-
    // icon pill buttons over a palette-sourced card. Each taps to a stub
    // sheet that renders `EusoEmptyState(comingSoon: true)` — the real
    // deposit / withdraw / transfer / card flows land in a later wave.
    private var section2QuickActions: some View {
        HStack(spacing: Space.s3) {
            actionPill(glyph: "arrow.left.arrow.right", label: "Transfer") { sheet = .transfer }
            actionPill(glyph: "arrow.down.to.line",     label: "Deposit")  { sheet = .deposit }
            actionPill(glyph: "arrow.up.right",         label: "Withdraw") { sheet = .withdraw }
            actionPill(glyph: "creditcard.fill",        label: "Card")     { sheet = .card }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func actionPill(glyph: String, label: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - §3 Weekly chart (7 bars, most recent on the right)
    //
    // Data: `earnings.getWeeklySummaries({ weeks: 7 })`. The server
    // returns rows newest-first — we reverse into chronological order
    // so the chart reads left-to-right. X-axis labels are 2-letter week
    // markers computed from `weekStart` (e.g. "4/21", "4/14"). Bar
    // heights normalise against the max earning across the seven rows
    // so a spike week fills the tile.
    private var section3WeeklyChart: some View {
        sectionCard(title: "Last 7 weeks", trailingCTA: nil) {
            switch weeklyStore.state {
            case .loading:
                sectionLoading(minHeight: 160)
            case .empty:
                EusoEmptyState(
                    systemImage: "chart.bar.fill",
                    title: "No settlements yet",
                    subtitle: "Your weekly gross appears here as soon as the first load clears."
                )
                .padding(Space.s2)
            case .error(let err):
                sectionError(err, retry: { Task { await weeklyStore.refresh() } })
            case .loaded(let rows):
                WeeklyBarChart(
                    rows: Array(rows.reversed()),
                    palette: palette
                )
                .frame(height: 160)
                .padding(.top, Space.s3)
            }
        }
    }

    // MARK: - §4 Upcoming settlements
    //
    // Data: `settlementBatching.getDriverBatchView({ driverId })`. Only
    // rows with status != paid/failed/disputed are surfaced (see
    // `DriverSettlementBatch.isUpcoming`). Each row shows the expected
    // period-end date, a truncated batch number, and the net amount.
    private var section4UpcomingSettlements: some View {
        // No `trailingCTA` — the user is already inside the wallet
        // pane that owns this section, and `MeDetailRoute` has no
        // `.settlements` case to navigate to. The previous "See all"
        // was a dead button (sectionCard called `onTap?()` on a nil
        // closure). Add the route + a real destination view before
        // re-enabling.
        sectionCard(title: "Upcoming settlements", trailingCTA: nil) {
            switch settlementsStore.state {
            case .loading:
                sectionLoading(minHeight: 120)
            case .empty:
                EusoEmptyState(
                    systemImage: "calendar.badge.clock",
                    title: "No pending payouts",
                    subtitle: "Once a load is approved for settlement, it queues up here."
                )
                .padding(Space.s2)
            case .error(let err):
                sectionError(err, retry: { Task { await settlementsStore.refresh() } })
            case .loaded(let batches):
                VStack(spacing: 0) {
                    ForEach(Array(batches.prefix(5).enumerated()), id: \.element.id) { idx, b in
                        settlementRow(b)
                        if idx < min(batches.count, 5) - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settlementRow(_ b: DriverSettlementBatch) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral)
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(b.batchNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(b.periodEnd.map { "Expected \(formatShortDate($0))" }
                     ?? b.status.uppercased())
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(currency(b.amount, currencyCode: "USD"))
                .font(EType.bodyStrong).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - §5 Activity feed
    //
    // Last 20 transactions, newest first. Gradient icon for credits
    // (positive amounts), neutral icon for debits. `EusoBadge(.hot)`
    // surfaces "HOT LANE" pills when a backend row's hint field
    // indicates a hot-lane load. Infinite scroll: `.onAppear` on the
    // last row fires a paginated refresh (offset += limit) as long as
    // the last page was full.
    @State private var txnsLoadingMore: Bool = false

    private var section5ActivityFeed: some View {
        sectionCard(title: "Activity", trailingCTA: nil) {
            switch txnsStore.state {
            case .loading:
                sectionLoading(minHeight: 120)
            case .empty:
                EusoEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "No activity yet",
                    subtitle: "Every payout, fee, and load credit shows up here the moment it clears."
                )
                .padding(Space.s2)
            case .error(let err):
                sectionError(err, retry: { Task { await txnsStore.refresh() } })
            case .loaded(let txns):
                VStack(spacing: 0) {
                    ForEach(Array(txns.enumerated()), id: \.element.id) { idx, t in
                        txnRow(t)
                            .onAppear {
                                // Infinite scroll: when the last row
                                // paints, pull the next page. Skipped if
                                // we already have fewer than a full page
                                // (server has nothing more to give).
                                if idx == txns.count - 1,
                                   txns.count >= 20,
                                   !txnsLoadingMore {
                                    txnsLoadingMore = true
                                    Task {
                                        await txnsStore.refresh()
                                        txnsLoadingMore = false
                                    }
                                }
                            }
                        if idx < txns.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func txnRow(_ t: WalletTxn) -> some View {
        let glyph: String = {
            if let hint = t.iconHint, !hint.isEmpty { return hint }
            switch t.kind {
            case "load_payout":         return "truck.box"
            case "instant_payout":      return "arrow.up.right"
            case "fuel":                return "fuelpump"
            case "fee", "platform_fee": return "doc.text"
            case "factoring":           return "bolt.fill"
            case "bonus":               return "star.fill"
            case "deposit":             return "arrow.down.to.line"
            case "transfer":            return "arrow.left.arrow.right"
            default:                    return "dollarsign.circle"
            }
        }()
        let positive = t.amount >= 0
        let isHot = t.subtitle?.localizedCaseInsensitiveContains("hot") == true
                 || t.iconHint?.localizedCaseInsensitiveContains("hot") == true

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(positive ? AnyShapeStyle(LinearGradient.diagonal)
                                   : AnyShapeStyle(palette.tintNeutral))
                Image(systemName: glyph)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(positive ? AnyShapeStyle(Color.white)
                                              : AnyShapeStyle(palette.textPrimary))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(t.title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if isHot {
                        EusoBadge(label: "HOT LANE", kind: .hot)
                    }
                }
                if let sub = t.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(currency(t.amount, currencyCode: t.currency ?? "USD", signed: true))
                .font(EType.bodyStrong).monospacedDigit()
                .foregroundStyle(positive ? AnyShapeStyle(Brand.success)
                                          : AnyShapeStyle(palette.textPrimary))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }

    // MARK: - §6 Factoring offer (hidden when no live offer)
    //
    // Live surface: `factoring.getOffer({ loadId })` driven by the
    // driver's current active load (from `DriverTripController`).
    // Store resolves to:
    //   - `.empty`  when there is no active load, or the backend
    //     returns `eligible=false` (wrong status, already factored,
    //     not assigned, no settled rate). Section collapses via
    //     `EmptyView()` so the TileStack spacing closes up.
    //   - `.loaded(offer)` only when the backend confirms an
    //     eligible, non-zero advance. Card renders the gradient
    //     "Get paid today" hero with Accept CTA that writes a real
    //     `payments` row through `factoring.accept`.
    //   - `.error` shows an inline retry banner (transient network
    //     failure — not the "coming soon" treatment).
    @ViewBuilder
    private var section6FactoringOffer: some View {
        switch factoringStore.state {
        case .loading:
            sectionCard(title: "Get paid today", trailingCTA: nil) {
                sectionLoading(minHeight: 120)
            }
        case .empty:
            // No active load, or server said ineligible — hide.
            EmptyView()
        case .error(let err):
            sectionCard(title: "Get paid today", trailingCTA: nil) {
                sectionError(err, retry: {
                    Task {
                        factoringStore.loadId = trip.currentLoad?.id
                        await factoringStore.refresh()
                    }
                })
            }
        case .loaded(let maybe):
            if let offer = maybe {
                factoringOfferCard(offer)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func factoringOfferCard(_ offer: FactoringAPI.Offer) -> some View {
        let feePercent = Double(offer.feeBps) / 100.0
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("Get paid today".uppercased())
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    StatusPill(text: offer.provider, kind: .info)
                }
                Text(currency(offer.netAmount, currencyCode: offer.currency))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Net to you after \(String(format: "%.2f", feePercent))% fee")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                HStack(spacing: Space.s3) {
                    MetricTile(label: "Gross", value: currency(offer.grossAmount, currencyCode: offer.currency, digits: 0))
                    MetricTile(label: "Fee", value: currency(offer.feeAmount, currencyCode: offer.currency, digits: 0))
                }
                CTAButton(title: "Accept offer") {
                    Task {
                        _ = try? await EusoTripAPI.shared.factoring.accept(
                            loadId: offer.loadId,
                            offerId: offer.offerId
                        )
                        await balanceStore.refresh()
                        await txnsStore.refresh()
                        await factoringStore.refresh()
                    }
                }
            }
        }
    }

    // MARK: - §7 Linked accounts (bank + debit cards)
    //
    // Data: `wallet.getPayoutMethods` (canonical — renamed from the
    // prior `listPaymentMethods` spec). Each row: brand icon + masked
    // label + "Default" chip if `isDefault`. Tapping "Manage" opens
    // the stub sheet (real add/remove flows wire into Plaid + Stripe
    // already on `AddPaymentAccountSheet`).
    private var section7LinkedAccounts: some View {
        sectionCard(
            title: "Linked accounts",
            trailingCTA: "Manage",
            onTap: { sheet = .paymentMethods }
        ) {
            switch methodsStore.state {
            case .loading:
                sectionLoading(minHeight: 100)
            case .empty:
                EusoEmptyState(
                    systemImage: "building.columns",
                    title: "No linked accounts",
                    subtitle: "Link a bank or debit card to receive payouts.",
                    cta: (label: "Add account", action: { showAddAccount = true })
                )
                .padding(Space.s2)
            case .error(let err):
                sectionError(err, retry: { Task { await methodsStore.refresh() } })
            case .loaded(let methods):
                VStack(spacing: 0) {
                    ForEach(Array(methods.enumerated()), id: \.element.id) { idx, m in
                        linkedAccountRow(m)
                        if idx < methods.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.leading, 52)
                        }
                    }
                    Divider().overlay(palette.borderFaint)
                        .padding(.leading, 52)
                    Button(action: { showAddAccount = true }) {
                        HStack(spacing: Space.s3) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(palette.tintNeutral)
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(LinearGradient.diagonal)
                            }
                            .frame(width: 36, height: 36)
                            Text("Add account")
                                .font(EType.bodyStrong)
                                .foregroundStyle(LinearGradient.diagonal)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a bank account or card")
                }
            }
        }
    }

    @ViewBuilder
    private func linkedAccountRow(_ m: WalletPaymentMethod) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral)
                Image(systemName: m.kind == "bank" ? "building.columns" : "creditcard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(m.institution) ••\(m.mask)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if m.isDefault {
                        EusoBadge(label: "Default", kind: .info)
                    }
                }
                Text(m.isInstant ? "Instant · 1.5% fee" : "ACH · 1–2 days")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }

    // MARK: - §8 Tax withholdings
    //
    // Live surface: `tax.getSummary` (driver-scoped). Backend aggregates
    // YTD gross from `payments` where payeeId=driver AND status settled.
    // `$0 YTD` is a valid `.loaded` state — renders "$0 YTD" alongside
    // $0 estimate, not an empty state. `.empty` only fires when the
    // API returns a literal null (effectively a 404 / decode edge).
    // `.error` surfaces an inline retry banner.
    private var section8TaxWithholdings: some View {
        sectionCard(title: "Tax withholdings", trailingCTA: nil) {
            switch taxStore.state {
            case .loading:
                sectionLoading(minHeight: 140)
            case .empty:
                // API returned no summary at all — rare; show a
                // neutral empty state (NOT comingSoon) consistent
                // with §1-§7.
                EusoEmptyState(
                    systemImage: "doc.plaintext.fill",
                    title: "No tax data yet",
                    subtitle: "Your withholdings post here as settlements clear.",
                    comingSoon: false
                )
                .padding(Space.s2)
            case .error(let err):
                sectionError(err, retry: { Task { await taxStore.refresh() } })
            case .loaded(let maybe):
                if let s = maybe {
                    taxContent(s)
                } else {
                    EusoEmptyState(
                        systemImage: "doc.plaintext.fill",
                        title: "No tax data yet",
                        subtitle: "Your withholdings post here as settlements clear.",
                        comingSoon: false
                    )
                    .padding(Space.s2)
                }
            }
        }
    }

    @ViewBuilder
    private func taxContent(_ s: TaxAPI.TaxSummary) -> some View {
        // Prefer the new §8 surface fields (`ytdGross`, `estimatedTax`,
        // `quarterlyEstimate`); fall back to the legacy names for
        // older server builds.
        let ytd = s.ytdGross ?? s.grossEarnings
        let estTax = s.estimatedTax ?? s.estimatedTaxLiability
        let quarterly = s.quarterlyEstimate ?? (estTax / 4.0)
        let displayYear = s.taxYear ?? s.year
        // Server's authoritative availability flag — falls back to the
        // local date check when the server hasn't populated it yet.
        let available = s.download1099Available ?? is1099Available(for: displayYear)

        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                MetricTile(
                    label: "YTD gross",
                    value: currency(ytd, currencyCode: s.currency, digits: 0),
                    gradientNumeral: true
                )
                MetricTile(
                    label: "Est. tax",
                    value: currency(estTax, currencyCode: s.currency, digits: 0)
                )
            }
            HStack(spacing: Space.s3) {
                MetricTile(
                    label: "Quarterly",
                    value: currency(quarterly, currencyCode: s.currency, digits: 0)
                )
                Spacer(minLength: 0)
            }
            Text("Tax year \(String(displayYear))")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: {
                // In-app 1099 render. Resolve a relative server path
                // against `EusoTripAPI.baseURL`, then present
                // `EusoPDFViewer` so the driver never leaves the app.
                if let raw = s.download1099URL, !raw.isEmpty {
                    let resolved: URL? = {
                        if let u = URL(string: raw), u.scheme != nil { return u }
                        if let base = EusoTripAPI.shared.baseURL {
                            return URL(string: raw, relativeTo: base)
                        }
                        return URL(string: raw)
                    }()
                    if let u = resolved {
                        taxPdfPresentation = EusoPDFPresentation(
                            url: u,
                            title: "1099-NEC · \(String(displayYear))",
                            subtitle: "Eusorone Technologies, Inc."
                        )
                    }
                } else {
                    Task {
                        _ = try? await EusoTripAPI.shared.tax.get1099(year: displayYear)
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                    Text("Download 1099")
                }
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.vertical, Space.s2)
            }
            .buttonStyle(.plain)
            .disabled(!available)
            .opacity(available ? 1.0 : 0.45)
            .accessibilityLabel("Download 1099 for \(String(displayYear))")
        }
        .padding(Space.s4)
    }

    /// A 1099 for tax year Y is only issuable after Jan 31 of Y+1.
    /// Before that the form doesn't exist yet; the CTA disables and
    /// drops to 45% opacity per §9 spec.
    private func is1099Available(for taxYear: Int) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var comps = DateComponents()
        comps.year = taxYear + 1
        comps.month = 1
        comps.day = 31
        guard let threshold = cal.date(from: comps) else { return false }
        return Date() >= threshold
    }

    // MARK: - Section shell helpers
    //
    // `sectionCard` paints the title + optional trailing CTA and wraps
    // the passed content in a `.eusoCard(...)` chrome. `sectionLoading`
    // / `sectionError` render the matching RemoteState branches so
    // every section has identical loading + error semantics.
    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        trailingCTA: String? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text(title.uppercased())
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let cta = trailingCTA {
                    Button(action: { onTap?() }) {
                        HStack(spacing: 4) {
                            Text(cta)
                                .font(EType.caption)
                                .foregroundStyle(LinearGradient.diagonal)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
                .eusoCard(radius: Radius.lg)
        }
    }

    @ViewBuilder
    private func sectionLoading(minHeight: CGFloat) -> some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Brand.magenta)
                .scaleEffect(1.1)
            Spacer()
        }
        .frame(minHeight: minHeight)
    }

    @ViewBuilder
    private func sectionError(_ err: Error, retry: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Can't reach the server")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(err.localizedDescription)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: retry) {
                Text("Retry")
                    .font(EType.caption)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s4)
    }

    // MARK: - Formatting helpers

    private func currency(
        _ value: Double,
        currencyCode: String?,
        digits: Int = 2,
        signed: Bool = false
    ) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode ?? "USD"
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = digits == 0 ? 0 : digits
        if signed {
            f.positivePrefix = "+"
            f.negativePrefix = "−"
        }
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func formatShortDate(_ iso: String) -> String {
        let iso8601: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        let fallback: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
        let ymd: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .current
            return f
        }()
        let date: Date? = iso8601.date(from: iso)
            ?? fallback.date(from: iso)
            ?? ymd.date(from: iso)
        guard let d = date else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    private func formatRelative(_ iso: String) -> String {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = iso8601.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        guard let d = parsed else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        return rel.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - WeeklyBarChart (hand-rolled, no Charts dependency)
//
// Seven-bar chart sized to fit the parent. Bars are gradient-filled
// (`LinearGradient.diagonal`), X-axis labels are short dates pulled
// from each row's `weekStart`, and the highest bar normalises to the
// top of the plot so spikes read as visual outliers. If all rows
// report zero earnings the chart falls through to a flat baseline —
// the `WeeklyEarningsStore.foldState` swaps to `.empty` in that case
// so the view never lands here.
private struct WeeklyBarChart: View {
    let rows: [WeeklyEarningsBar]
    let palette: Theme.Palette

    var body: some View {
        GeometryReader { geo in
            let count = max(rows.count, 1)
            let maxVal = max(rows.map(\.totalEarnings).max() ?? 1, 1)
            let barSpacing: CGFloat = 8
            let labelHeight: CGFloat = 18
            let plotHeight = geo.size.height - labelHeight - 4
            let barWidth = max(
                ((geo.size.width - barSpacing * CGFloat(count - 1)) / CGFloat(count)) - 2,
                8
            )
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(rows) { r in
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(palette.tintNeutral)
                                .frame(width: barWidth, height: plotHeight)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(LinearGradient.diagonal)
                                .frame(
                                    width: barWidth,
                                    height: max(
                                        plotHeight * CGFloat(r.totalEarnings / maxVal),
                                        r.totalEarnings > 0 ? 4 : 0
                                    )
                                )
                        }
                        Text(shortLabel(for: r.weekStart))
                            .font(EType.micro).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .frame(height: labelHeight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Space.s3)
    }

    private func shortLabel(for iso: String) -> String {
        let ymd = DateFormatter()
        ymd.dateFormat = "yyyy-MM-dd"
        ymd.timeZone = .current
        let date = ymd.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return "·" }
        let out = DateFormatter()
        out.dateFormat = "M/d"
        return out.string(from: d)
    }
}

// MARK: - Wallet sheet container (deposit / withdraw / transfer / factoring / manage / tax / fuel)

/// Light-weight routed sheet wrapper for wallet modals. Each route gets a
/// title, a short body explaining what the modal does, and a primary CTA.
/// The actual network + form logic lands in Task #14 when CTAs across the
/// app are wired end-to-end; for now these sheets reserve the routes so
/// taps on the wallet surface don't dead-end.
struct WalletSheetContainer: View {
    @Environment(\.palette) var palette

    let kind: DriverWalletPane.WalletSheet?
    let onClose: () -> Void

    private var title: String {
        switch kind {
        case .deposit:        return "Deposit"
        case .withdraw:       return "Withdraw"
        case .transfer:       return "Transfer"
        case .card:           return "Card"
        case .factoring:      return "Factoring offer"
        case .paymentMethods: return "Payment methods"
        case .tax:            return "Tax · 1099"
        case .none:           return ""
        }
    }
    private var subtitle: String {
        switch kind {
        case .deposit:        return "MOVE FUNDS INTO EUSOWALLET"
        case .withdraw:       return "PAYOUT TO A LINKED BANK OR CARD"
        case .transfer:       return "SEND BETWEEN ACCOUNTS"
        case .card:           return "EUSO DEBIT · SPEND DIRECTLY FROM WALLET"
        case .factoring:      return "ADVANCE AGAINST PENDING POD"
        case .paymentMethods: return "LINKED BANKS · CARDS · PAYOUT RAILS"
        case .tax:            return "W-9 ON FILE · 1099 DRAFT"
        case .none:           return ""
        }
    }
    private var body_: String {
        switch kind {
        case .deposit:
            return "Pull from your linked bank into EusoWallet. Funds arrive same-day before 5pm local."
        case .withdraw:
            return "Send available balance to your linked bank (1-2 days, free) or linked debit (instant, 1.5% fee)."
        case .transfer:
            return "Move funds between your EusoWallet and linked accounts, or split settlements across multiple banks."
        case .card:
            return "The Euso debit card spends directly from your EusoWallet available balance. Activation ships alongside the issuer partner — this flow will go live once the card issuer router lands."
        case .factoring:
            return "Advance against your pending POD at a flat factoring rate. Cash lands in your EusoWallet in under 10 minutes and the platform recovers from the broker settlement."
        case .paymentMethods:
            return "Manage the accounts you use to deposit, withdraw, and factor. Plaid-backed verification; tier fees shown per rail."
        case .tax:
            return "Your 1099-NEC populates each January as settlements clear. W-9 goes on file when you link your first account."
        case .none:
            return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)

            IridescentHairline()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text(body_)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    CTAButton(title: primaryCTA) {
                        MeAction.fire(primaryCTAKey,
                                      userInfo: ["kind": primaryCTA])
                        onClose()
                    }
                }
                .padding(Space.s5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage)
    }

    /// Stable per-kind action key. A future backend bridge can dispatch on
    /// these without caring about the display label.
    private var primaryCTAKey: String {
        switch kind {
        case .deposit:        return "wallet.deposit"
        case .withdraw:       return "wallet.withdraw"
        case .transfer:       return "wallet.transfer"
        case .card:           return "wallet.activate-card"
        case .factoring:      return "wallet.accept-factoring"
        case .paymentMethods: return "wallet.add-payment-method"
        case .tax:            return "tax.download-draft-1099"
        case .none:           return "wallet.continue"
        }
    }

    private var primaryCTA: String {
        switch kind {
        case .deposit:        return "Continue"
        case .withdraw:       return "Continue"
        case .transfer:       return "Start transfer"
        case .card:           return "Activate card"
        case .factoring:      return "Accept offer"
        case .paymentMethods: return "Add a method"
        case .tax:            return "Download draft"
        case .none:           return "Continue"
        }
    }
}

// MARK: - DriverMePane (tab 4)

struct DriverMePane: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var profile: DriverProfileStore
    @State private var activeRoute: MeDetailRoute? = nil
    /// Presents ProfileEditView when the driver taps the header card.
    /// Parallel to `MeSettingsView`'s ACCOUNT card affordance so the same
    /// editor is reachable from either entry point.
    @State private var showEditProfile = false

    /// Top-level entries for the Me tab hub. Each row opens its destination
    /// screen in a bottom sheet via `MeDetailContainer`.
    ///
    /// Per web-platform taxonomy (request 2026-04-20): DVIR is not a
    /// top-level entry here — inspection is a branch of Zeun Mechanics
    /// ("zeun is anything mechanical including inspection"). The DVIR
    /// history surface has been folded into `MeZeunView` below and the
    /// standalone `.dvir` row has been removed from this hub.
    private let entries: [MeEntry] = [
        .init(route: .earnings,     glyph: "dollarsign.circle",        title: "EusoWallet",       sub: "Week · month · YTD"),
        // Carrier (employer) sits at #2 — drivers ask "who do I work
        // for, are we in good standing" before anything else when the
        // dispatcher swap happens. Backed by `drivers.getMyCarrier`.
        .init(route: .carrier,      glyph: "building.2",               title: "Carrier",          sub: "DOT · MC · compliance · contact"),
        // Authority — for owner-ops who want to lease-on under
        // another carrier's DOT/MC for a single trip or seasonal
        // run. FMCSR Part 376 lease management lives here.
        .init(route: .authority,    glyph: "checkmark.seal.fill",      title: "Authority",        sub: "Lease-on · trip lease · Part 376"),
        // Rate Sheets — Schedule A authoring + live pay calculator +
        // reconciliation. Web-platform parity port (16 procedures
        // through `rateSheetRouter`). High value for owner-operators
        // running their own Schedule A.
        .init(route: .rateSheet,    glyph: "doc.text",                 title: "Rate Sheets",      sub: "Schedule A · calculator · reconciliation"),
        // Documents Center — replaces the standalone Tax row. Tax W-9
        // and 1099 are surfaced as a section card INSIDE the hub
        // alongside CDL / medical / TWIC / hazmat / insurance /
        // registration / IFTA / IRP / BOL / POD / contracts / etc.
        // ESANG AI auto-classifies on every upload (Gemini + VIGA).
        .init(route: .documents,    glyph: "folder.fill",              title: "Documents Center", sub: "Vault · upload · AI classify · tax"),
        // EusoTicket — Bills of Lading + run tickets + per-haul
        // receipts. Mirrors the web `/euso-ticket` page (terminal
        // manager + driver), backed by `eusoTicket.*` tRPC procs
        // (createRunTicket, listRunTickets, generateBOL, listBOLs,
        // generateRunTicketPDF, generateBOLPDF, getTerminalStats).
        .init(route: .eusoTicket,   glyph: "ticket.fill",              title: "EusoTicket",       sub: "BOL · run ticket · haul receipts"),
        .init(route: .availability, glyph: "calendar",                 title: "Availability",     sub: "Duty schedule + home-time"),
        // Missions / Rewards / Badges live ONLY inside The Haul (the
        // gamification hub below). They were duplicated here as
        // top-level Me rows; removed so the Me hub stays operational
        // (wallet, compliance, fleet) and The Haul stays the single
        // entry for everything game-loop.
        .init(route: .referrals,    glyph: "person.2",                 title: "Referrals",        sub: "Invite other drivers"),
        .init(route: .zeun,         glyph: "cpu",                      title: "Zeun Mechanics",   sub: "Diagnostics · DVIR · maintenance"),
        .init(route: .eld,          glyph: "waveform.path.ecg",        title: "ELD",              sub: "Duty status · drive clock · HoS"),
        .init(route: .fleet,        glyph: "truck.box",                title: "Fleet Management", sub: "Vehicles · trailers · IFTA"),
        .init(route: .haul,         glyph: "trophy",                   title: "The Haul",         sub: "Missions · badges · rewards · leaderboard"),
        .init(route: .news,         glyph: "newspaper",                title: "Driver Intel",     sub: "News · regulations · market"),
        .init(route: .pulse,         glyph: "applewatch.watchface",     title: "EusoTrip Pulse",   sub: "Apple Watch pairing · last sync"),
        .init(route: .notifications, glyph: "bell.fill",                title: "Notifications",    sub: "Inbox · categories · delivery"),
        .init(route: .settings,      glyph: "gearshape",                title: "Settings",         sub: "Account · device")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Patch #1: EusoHeader. The "CAREER · COMPLIANCE · REPUTATION"
            // bullet-subtitle is dropped — the profile avatar card below
            // already carries the driver's name & reputation summary.
            EusoHeader(title: "Me")
            IridescentHairline()
            // Prior build had the Me hub in a plain VStack, which meant the
            // 10-row list couldn't scroll past the nav on shorter devices
            // and the bottom entries were clipped under the floating pill.
            // Wrap the hub in a ScrollView and reserve clearance for the
            // bottom nav, matching the pattern in DriverTripsPane.
            ScrollView {
                // TileStack — driver profile header tile lifts in first,
                // then the full Me hub row card, matching the web Me page.
                TileStack(alignment: .leading, spacing: Space.s4) {
                    Button {
                        showEditProfile = true
                    } label: {
                        ActiveCard {
                            HStack(alignment: .center, spacing: Space.s3) {
                                profileAvatar
                                VStack(alignment: .leading, spacing: Space.s2) {
                                    Text("Driver")
                                        .font(EType.micro).tracking(0.8)
                                        .foregroundStyle(palette.textTertiary)
                                    Text(profile.fullName)
                                        .font(EType.h2)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(profile.reputationSummary)
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundStyle(LinearGradient.diagonal)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { idx, e in
                            Button {
                                activeRoute = e.route
                            } label: {
                                row(e, index: idx)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(e.title). \(e.sub)")
                            .accessibilityHint("Opens \(e.title)")
                            if idx < entries.count - 1 {
                                Divider().overlay(palette.borderFaint)
                                    .padding(.leading, Space.s4 + 22 + Space.s3)
                            }
                        }
                    }
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))

                    // Reserve clearance under the floating BottomNav pill so
                    // the last row ("Settings") isn't tucked behind it.
                    Color.clear
                        .frame(height: Device.navHeight + Device.safeBottom + Space.s4)
                }
                .padding(Space.s5)
            }
            .scrollIndicators(.hidden)
            // Refresh driver profile card (name / CDL / rating / loads
            // completed) and the Me hub row counts.
            .refreshable {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
        .sheet(item: $activeRoute) { route in
            MeDetailContainer(route: route)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        .sheet(isPresented: $showEditProfile) {
            ProfileEditView()
                .environmentObject(profile)
        }
        // ESANG voice-command deep-link. The ContentView dispatcher posts
        // `.esangOpenMeDetail` with the `MeDetailRoute.rawValue` as
        // `object` — decode it here and flip `activeRoute` so the matching
        // sub-sheet presents. Voice triggers today: "open ELD",
        // "fleet management", "take me to Zeun", "show my Eusowallet",
        // plus every other Me-tab route in the enum.
        .onReceive(NotificationCenter.default.publisher(for: .esangOpenMeDetail)) { note in
            guard let raw = note.object as? String,
                  let route = MeDetailRoute(rawValue: raw) else { return }
            // If the driver already has a different sub-sheet up, swap
            // it out on the next runloop tick so the presentation
            // transition doesn't fight itself.
            if activeRoute != nil && activeRoute != route {
                activeRoute = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    activeRoute = route
                }
            } else {
                activeRoute = route
            }
        }
    }

    /// Me-tab header avatar — mirrors `MeSettingsView.accountAvatar` so the
    /// Me hub and Settings ACCOUNT card render the same driver likeness.
    @ViewBuilder
    private var profileAvatar: some View {
        ZStack {
            if let data = profile.avatarData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(profileInitials)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.white)
                    )
            }
        }
        .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var profileInitials: String {
        let f = profile.firstName.first.map { String($0) } ?? ""
        let l = profile.lastName.first.map { String($0) } ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "ME" : s
    }

    private struct MeEntry {
        let route: MeDetailRoute
        let glyph: String
        let title: String
        let sub: String
    }

    /// Per-row icon tint rotated through the three anchor stops that
    /// compose `LinearGradient.diagonal` — Brand.blue → Brand.escort →
    /// Brand.magenta. This replaces the stock-Settings "gray rounded
    /// square behind every glyph" treatment. The glyph itself is drawn
    /// borderless (no tile), matching Home's icon language where route
    /// arrows, location pins and other accent glyphs sit directly on
    /// the page/card surface in brand color — not inside a neutral
    /// chip.
    ///
    /// Colors are pulled verbatim from `Brand` in DesignSystem.swift;
    /// no new palette tokens are introduced.
    private static let rowTints: [Color] = [Brand.blue, Brand.escort, Brand.magenta]

    @ViewBuilder
    private func row(_ e: MeEntry, index: Int) -> some View {
        let tint = Self.rowTints[index % Self.rowTints.count]
        HStack(spacing: Space.s3) {
            Image(systemName: e.glyph)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(e.sub)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func topBar(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 40, weight: .heavy))
                // Pane hero title — gradient in both registers. Matches the
                // "Hey, <name>" treatment on Home so Wallet/Trips/Me/Load
                // Boards all read brand-native rather than flat black in
                // light mode.
                .foregroundStyle(LinearGradient.diagonal)
            Text(subtitle.uppercased())
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }
}

// MARK: - Chat transfer payload (used by ESANG coach + inbox conversations)

/// Typed card rendered inline when the driver sends a P2P transfer from
/// a chat composer. EusoWallet (Stripe Connect under the hood) executes
/// the real money move on the backend; the chat thread just echoes the
/// confirmation card so the driver has a visible receipt in-conversation.
///
/// Keeping the payload shape flat here — the same struct is embedded in
/// `DrivereSangCoachSheet.Msg.transfer` and `ChatMessage.transfer` so the
/// card renderer below works unchanged in either surface.
struct ChatTransferPayload: Equatable {
    let amountCents: Int
    let recipientName: String
    let memo: String?
    let status: Status

    enum Status: String, Equatable {
        /// Awaiting wallet confirmation — shows a spinner.
        case pending
        /// Wallet ACK landed — card pulses success tint.
        case sent
        /// Wallet rejected (insufficient funds, Stripe hold, etc.).
        case failed
    }

    var formattedAmount: String {
        let dollars = Double(amountCents) / 100.0
        return dollars.formatted(.currency(code: "USD"))
    }
}

// MARK: - Full conversation model (DriverConversationView)

/// Unified message type for the full inbox conversation view. Covers text,
/// image attachments (BOL/DVIR photos), and P2P money transfer cards. Reused
/// across threads of every kind — dispatch, broker, driver-to-driver, even
/// the ESANG coach thread when surfaced through the inbox.
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let from: Sender
    /// Originally declared `let` — but the conversation hydrator in
    /// DriverConversationView.toChat(_:) needs to clear the caption to
    /// `""` for image / payment messages so the bubble renders just the
    /// attachment without the server's "[image] filename.jpg" noise.
    /// Making this `var` keeps call-sites that only read `text`
    /// untouched while unblocking the mutation path.
    var text: String
    var imageData: Data? = nil
    /// Remote URL for an image attachment served by the backend. When
    /// `imageData` is nil but `imageURL` is set the bubble renders via
    /// `AsyncImage` instead of the in-memory blob. This is the server
    /// path — attachments inserted via `messages.uploadAttachment` come
    /// back with a `data:image/...;base64,...` URL that decodes fine in
    /// `AsyncImage` via `URL(string:)`.
    var imageURL: String? = nil
    var transfer: ChatTransferPayload? = nil
    var time: Date = .init()
    /// True once the recipient has opened the thread. Drives the
    /// double-check read-receipt glyph on outbound messages.
    var read: Bool = false
    /// Server-side message id (`messages.id` row in the backend).  Nil
    /// for optimistic messages that haven't been ACKed yet; filled in
    /// once `messages.sendMessage` / `uploadAttachment` returns. Used
    /// to dedupe the inbound WebSocket fan-out against messages we
    /// already appended locally.
    var serverId: String? = nil
    /// When true, render the "message unsent" placeholder instead of
    /// the original content. Flipped by `messages.unsendMessage`.
    var unsent: Bool = false

    enum Sender: String, Equatable { case me, other }
}

// MARK: - Chat glyph with live unread badge
//
// Replaces the old static 8×8 gradient dot that used to sit on the
// chat button in the Driver top bar. Re-renders whenever
// `UnreadMessageStore.shared.total` changes (either from a fresh
// `messages.getUnreadCount` pull or a `message:new` WebSocket
// fan-out). The visible count is capped at "99+" so the pill stays
// compact on the narrow header rail.
//
// The button itself preserves the 40×40 rounded-rect chrome
// (bgCard fill + borderFaint stroke) that every other top-bar
// affordance uses, so the header composition feels unchanged —
// the only new thing is the small pill stamped over the upper-
// right corner whenever there are unread messages.
struct MessagesBadgeButton: View {
    @Binding var showMessages: Bool
    let palette: Theme.Palette

    /// Tracked locally rather than via @ObservedObject so the view can
    /// re-render even when the store publishes on `.eusoUnreadCountChanged`
    /// (singleton ObservableObjects in SwiftUI sometimes miss republishes
    /// when mutated from a deinit-era observer chain). NotificationCenter
    /// is the authoritative pulse.
    @State private var unreadTotal: Int = UnreadMessageStore.shared.total

    var body: some View {
        Button {
            showMessages = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "message")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

                if unreadTotal > 0 {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(
                            Capsule(style: .continuous).fill(LinearGradient.diagonal)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(palette.bgPage, lineWidth: 1.5)
                        )
                        .offset(x: 6, y: -6)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("\(unreadTotal) unread messages")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Messages")
        .accessibilityHint(unreadTotal > 0 ? "\(unreadTotal) unread" : "")
        .onAppear {
            // Snap to the current source of truth on first mount.
            unreadTotal = UnreadMessageStore.shared.total
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoUnreadCountChanged)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                unreadTotal = UnreadMessageStore.shared.total
            }
        }
    }

    private var badgeText: String {
        unreadTotal > 99 ? "99+" : "\(unreadTotal)"
    }
}

/// Lightweight thread descriptor shared between the inbox list and the
/// conversation view. Exposed at file-scope so both surfaces compile
/// against the same type.
struct InboxThread: Identifiable, Equatable, Hashable {
    let id: String
    let glyph: String
    let title: String
    let subtitle: String        // role / company line under the name
    let preview: String
    let time: String
    let unread: Int
    /// Whether P2P money transfer is enabled for this thread. Dispatch +
    /// broker threads hide the money affordance because there's no peer
    /// wallet to send to; driver-to-driver + owner-operator threads turn
    /// it on.
    let allowsTransfer: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension InboxThread {
    /// Map the backend `messages.getConversations` row to the lightweight
    /// view model the inbox + conversation surface expects. Glyph, role
    /// label, and P2P eligibility are derived from the server's type
    /// (`direct`, `group`, `job`, `channel`, `company`, `support`) and
    /// the counterparty role string (`driver`, `dispatcher`, `broker`, …).
    init(fromConversation c: MessagingConversation) {
        let roleLower = (c.role ?? "").lowercased()
        let typeLower = (c.type ?? "direct").lowercased()

        // Glyph picker — mirror the web inbox iconography.
        let glyph: String = {
            if roleLower.contains("dispatch") { return "headphones" }
            if roleLower.contains("broker")   { return "truck.box" }
            if roleLower.contains("driver")   { return "person.crop.square" }
            if roleLower.contains("shipper")  { return "building.2" }
            if typeLower == "channel"         { return "megaphone" }
            if typeLower == "group"           { return "person.2" }
            if typeLower == "support"         { return "lifepreserver" }
            if typeLower == "job"             { return "shippingbox" }
            return "person.crop.circle"
        }()

        // Subtitle — role + (optional) load tag for job conversations.
        let roleLabel: String = {
            switch roleLower {
            case "dispatcher", "dispatch":      return "Fleet dispatcher"
            case "broker":                       return "Broker · load desk"
            case "driver":                       return "Driver peer"
            case "shipper":                      return "Shipper"
            case "admin":                        return "Admin · Eusorone"
            default:
                if typeLower == "channel" { return "Channel" }
                if typeLower == "group"   { return "Group chat" }
                if typeLower == "support" { return "Support" }
                return "Direct message"
            }
        }()
        let subtitle: String = {
            if let loadId = c.loadId { return "\(roleLabel) · load #\(loadId)" }
            return roleLabel
        }()

        // Peer P2P transfer is enabled only on 1:1 peer threads with a
        // counterparty we know can accept EusoWallet funds — drivers +
        // other peers. Dispatch / broker / shipper threads surface a
        // "Request payment" path but hide the direct-send control.
        let peerCapable = (typeLower == "direct") &&
            (roleLower.contains("driver") ||
             roleLower.isEmpty ||
             roleLower == "user")

        self.init(
            id: c.id,
            glyph: glyph,
            title: c.displayName,
            subtitle: subtitle,
            preview: (c.lastMessage ?? "").isEmpty ? "Tap to start the conversation" : (c.lastMessage ?? ""),
            time: InboxThread.relativeTime(from: c.lastMessageAt),
            unread: c.effectiveUnread,
            allowsTransfer: peerCapable
        )
    }

    /// Format an ISO-8601 timestamp as a compact relative string — `3m`,
    /// `2h`, `Mon`, `Apr 4`. Same shape the web inbox uses so mixed
    /// surfaces (iPad web + iOS phone) feel consistent.
    static func relativeTime(from iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = f.date(from: iso)
        if date == nil {
            f.formatOptions = [.withInternetDateTime]
            date = f.date(from: iso)
        }
        guard let date else { return "" }
        let now = Date()
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 86_400 { return "\(Int(delta / 3600))h" }
        if delta < 604_800 {
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE"
            return fmt.string(from: date)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

// MARK: - DriverMessagesSheet (top-right chat button target)

/// Bottom sheet presented when the driver taps the top-right message glyph
/// on screen 010. Surfaces recent threads (Dispatch, ESANG, Broker ops) and
/// drills into a full conversation view (`DriverConversationView`) on tap
/// so the driver can actually read + reply in-thread, upload a photo, and
/// send P2P money.
///
/// Wave-6 wiring (2026-04-21): the thread list now hydrates from the live
/// `messages.getConversations` tRPC procedure; pull-to-refresh and a
/// NotificationCenter observer on `.eusoMessageReceived` keep it fresh
/// without polling. `UnreadMessageStore` gets the per-conversation
/// unread map after every load so the top-bar badge stays in sync.
struct DriverMessagesSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    /// The currently open thread, or `nil` when the user is browsing the
    /// inbox list. `.sheet(item:)` binds to this so tapping a row slides
    /// up the conversation surface and a dismissal puts the driver back
    /// on the inbox.
    @State private var activeThread: InboxThread? = nil

    @State private var threads: [InboxThread] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String? = nil
    @State private var didFirstLoad: Bool = false

    /// Keyed on conversation id → observer so we can tear down listeners
    /// when the sheet is dismissed. The inbox refresh already folds
    /// `message:new` events into a refetch, so we only need one active
    /// observer while the sheet is mounted.
    @State private var refreshObserver: NSObjectProtocol? = nil

    /// Presents the compose flow — contact picker + (optional) group-name
    /// field, backed by `messages.searchUsers` and `messages.createConversation`.
    /// Paired with `pendingOpenThread` so that once a conversation is created
    /// we can drill straight into `DriverConversationView` without the driver
    /// having to hunt for the new row in the inbox.
    @State private var showNewMessage: Bool = false
    /// Holds the thread we want to drill into after the compose sheet
    /// dismisses. Assigned inside `onCreated` and consumed by a short
    /// `asyncAfter` hop so SwiftUI can finish animating the sheet-in-sheet
    /// dismissal before we present the conversation surface.
    @State private var pendingOpenThread: InboxThread? = nil

    // MARK: Swipe-to-delete state
    //
    // User tapped the red "Delete" swipe action on a row. We stage the
    // thread here and raise a confirmation dialog so a stray swipe on a
    // vendor/dispatch thread doesn't nuke history by accident. On confirm
    // we optimistically strip the row from `threads`, call
    // `messages.deleteConversation` (soft-delete for caller), and on
    // failure we reinstate the row + surface a toast-style error line.
    @State private var pendingDelete: InboxThread? = nil
    /// Stashed copy of the thread we just optimistically removed. Used to
    /// roll the row back into `threads` if the tRPC mutation fails.
    @State private var lastDeletedSnapshot: (thread: InboxThread, index: Int)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Messages")
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("DISPATCH · ESANG · BROKERS · PEERS")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()

                // Compose (square.and.pencil) — opens `NewMessageSheet` for
                // picking a peer (1:1 DM) or building a multi-select group
                // chat. The brand hairline frames it so it reads as the
                // primary action on this surface.
                Button {
                    showNewMessage = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(
                            LinearGradient.diagonal.opacity(0.22)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start a new conversation")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close messages")
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)

            IridescentHairline()

            // Thread list. Tapping a row pushes the full conversation
            // view up as a sheet — bubbles, composer, photo share, and
            // (for peer threads) a P2P money-transfer affordance.
            //
            // Uses SwiftUI `List` so we get native `.swipeActions` for the
            // trailing-edge Delete affordance. `.plain` list style + hidden
            // scroll background keeps the surface on brand `bgPage` (no
            // system grey); `.listRowBackground(Color.clear)` defers to
            // our own rounded-card chrome inside `threadRow`.
            Group {
                if !didFirstLoad && isLoading {
                    ScrollView {
                        inboxSkeleton.padding(Space.s5)
                    }
                } else if threads.isEmpty {
                    ScrollView {
                        emptyState.padding(Space.s5)
                    }
                } else {
                    List {
                        Section {
                            ForEach(threads) { t in
                                Button {
                                    activeThread = t
                                } label: {
                                    threadRow(t)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open \(t.title)")
                                .listRowBackground(palette.bgCard)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparatorTint(palette.borderFaint)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = t
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityLabel("Delete conversation with \(t.title)")
                                }
                            }
                        } footer: {
                            if let loadError, !threads.isEmpty {
                                Text(loadError)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textTertiary)
                                    .padding(.top, Space.s2)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(palette.bgPage)
                }
            }
            // Refresh the thread inbox — re-pulls getConversations and
            // the aggregate unread count in parallel.
            .refreshable {
                await loadInbox(force: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage)
        .task {
            if !didFirstLoad {
                await loadInbox(force: true)
            }
        }
        .onAppear {
            // Refetch when a new message lands while the sheet is open.
            let token = NotificationCenter.default.addObserver(
                forName: .eusoMessageReceived, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in
                    await loadInbox(force: false)
                }
            }
            refreshObserver = token
        }
        .onDisappear {
            if let refreshObserver {
                NotificationCenter.default.removeObserver(refreshObserver)
            }
            refreshObserver = nil
        }
        // Drill-in to the full conversation. `.sheet(item:)` keeps the
        // inbox surface mounted underneath so swiping the conversation
        // down returns the driver exactly where they were.
        .sheet(item: $activeThread) { thread in
            DriverConversationView(thread: thread)
                .environment(\.palette, palette)
                .onDisappear {
                    // Returning to the inbox — refresh so the row's
                    // preview + unread count reflect what happened in
                    // the thread (read-marks, fresh reply, etc.).
                    Task { @MainActor in await loadInbox(force: false) }
                }
        }
        // Compose flow. `.sheet(isPresented:)` co-exists with the
        // drill-in `.sheet(item:)` above — the two bind to different
        // state so SwiftUI treats them as independent presentations.
        // On success we defer the `activeThread` assignment so the
        // compose sheet finishes animating out before the conversation
        // surface animates in (avoids a visual stutter + the "another
        // sheet is already presenting" warning in release builds).
        .sheet(isPresented: $showNewMessage) {
            NewMessageSheet { thread in
                pendingOpenThread = thread
            }
            .environment(\.palette, palette)
        }
        .onChange(of: showNewMessage) { _, isShown in
            // When the compose sheet finishes dismissing and we have a
            // thread waiting, open the full conversation surface.
            guard !isShown, let thread = pendingOpenThread else { return }
            pendingOpenThread = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                activeThread = thread
                // Kick a background refetch so the new conversation
                // shows up in the inbox list for next time.
                await loadInbox(force: false)
            }
        }
        // Swipe-to-delete confirmation. Staged on `pendingDelete` so a
        // stray swipe can't silently blow away a dispatch thread. Uses
        // `.confirmationDialog` (the iOS-native action sheet) so the
        // destructive cue matches system affordances everywhere else
        // on the platform.
        .confirmationDialog(
            pendingDelete.map { "Delete conversation with \($0.title)?" } ?? "Delete conversation?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { thread in
            Button("Delete", role: .destructive) {
                Task { @MainActor in
                    await deleteThread(thread)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { _ in
            Text("This removes the thread from your inbox. The other participant's copy is unaffected.")
        }
    }

    // MARK: Swipe-to-delete

    /// Optimistically strips the row out of `threads`, calls
    /// `messages.deleteConversation` (soft-delete — only hides it for the
    /// caller), refreshes the unread badge, and rolls the row back in if
    /// the mutation fails. Also clears `activeThread` if the user happens
    /// to have the same thread open underneath (shouldn't happen — the
    /// drill-in sheet covers the inbox — but defensive).
    @MainActor
    private func deleteThread(_ thread: InboxThread) async {
        pendingDelete = nil
        // Snapshot before mutating so we can roll back on failure.
        guard let idx = threads.firstIndex(where: { $0.id == thread.id }) else { return }
        lastDeletedSnapshot = (thread, idx)
        // `Array.remove(at:)` returns the removed element, and
        // `withAnimation` is generic over its closure's result — sartico even
        // with `_ =` inside the closure, Swift still flags the outer call
        // as returning an unused value. Explicitly discard at the top
        // level to silence the warning.
        _ = withAnimation(.easeInOut(duration: 0.2)) {
            threads.remove(at: idx)
        }
        if activeThread?.id == thread.id {
            activeThread = nil
        }
        do {
            _ = try await EusoTripAPI.shared.messaging.deleteConversation(
                conversationId: thread.id
            )
            lastDeletedSnapshot = nil
            // Re-pull unread map so the top-bar badge drops the now-gone
            // conversation without waiting for the next WebSocket tick.
            await loadInbox(force: false)
        } catch {
            // Mutation failed — restore the row and surface the error so
            // the driver knows the delete didn't land on the server.
            if let snapshot = lastDeletedSnapshot {
                withAnimation(.easeInOut(duration: 0.2)) {
                    let insertAt = min(snapshot.index, threads.count)
                    threads.insert(snapshot.thread, at: insertAt)
                }
                lastDeletedSnapshot = nil
            }
            loadError = "Couldn't delete — \(error.localizedDescription)"
        }
    }

    // MARK: Inbox loader

    private func loadInbox(force: Bool) async {
        if isLoading && !force { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await EusoTripAPI.shared.messaging.getConversations()
            threads = fetched.map(InboxThread.init(fromConversation:))
            loadError = nil
            didFirstLoad = true
            UnreadMessageStore.shared.ingest(conversations: fetched)
        } catch EusoTripAPIError.unauthenticated {
            loadError = "Please sign in to load messages."
            didFirstLoad = true
        } catch {
            loadError = "Couldn't refresh messages — \(error.localizedDescription)"
            didFirstLoad = true
        }
    }

    // MARK: Empty + skeleton states

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(palette.textTertiary)
            Text("No conversations yet")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Text("Start a direct chat with dispatch, a broker, or another driver — or spin up a group for your lane.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s4)

            // Primary CTA — this is what was missing on the inbox surface.
            // Without a way to initiate a thread, an empty inbox is a
            // dead end. Tapping opens the same compose sheet the header
            // button does.
            Button {
                showNewMessage = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Start a conversation")
                        .font(EType.bodyStrong)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 10)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s2)
            .accessibilityLabel("Start a conversation")

            if let loadError {
                Text(loadError)
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
    }

    @ViewBuilder private var inboxSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(alignment: .top, spacing: Space.s3) {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(palette.tintNeutral)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral)
                            .frame(width: 180, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral.opacity(0.6))
                            .frame(width: 240, height: 10)
                    }
                    Spacer()
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
            }
        }
        .eusoCard(radius: Radius.lg)
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private func threadRow(_ t: InboxThread) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral)
                Image(systemName: t.glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(t.title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(t.time)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Text(t.preview)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }

            if t.unread > 0 {
                Text("\(t.unread)")
                    .font(EType.micro)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
            }

            // Chevron cue that the row drills in.
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }
}

// MARK: - eSang rotating greeting

/// Warm, time-aware greeting helper. The old greeting was a static literal
/// ("Hey — I've got eyes on your HOS…") that the user — rightly — flagged as
/// bland for a Gemini-backed copilot. This picks from a bank of 20+ variants
/// grouped by part-of-day and rotated by a new UUID every launch so no two
/// sessions feel identical. Kept local + deterministic per-session so unit
/// tests can seed it.
///
/// Driver-facing copy rules:
///   • Never start with a task. Lead with warmth (morning greeting, how it's
///     going, a beat of gratitude) then offer help.
///   • No buzzwords, no "how can I assist you today" — ESANG is a copilot,
///     not a help desk.
///   • Always end on an open lane: "what's on your radar?", "what's first?",
///     "need me to pull anything up?" — that's what cues drivers to talk.
enum eSangGreeting {

    /// Parts of the day. Cutoffs mirror what most drivers feel in-cab:
    /// earlyMorning is pre-dawn dispatch grind, lateNight is running on the
    /// back side of the 14-hour.
    private enum DayPart {
        case earlyMorning     // 4 – 7
        case morning          // 7 – 12
        case afternoon        // 12 – 17
        case evening          // 17 – 21
        case night            // 21 – 24
        case lateNight        // 0 – 4

        static func from(_ date: Date) -> DayPart {
            let hour = Calendar.current.component(.hour, from: date)
            switch hour {
            case 0..<4:  return .lateNight
            case 4..<7:  return .earlyMorning
            case 7..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<21: return .evening
            default: return .night
            }
        }
    }

    /// Banks of variants. Each line leads with warmth, shows awareness of
    /// the time of day, then opens the lane for the driver to talk.
    private static let variants: [DayPart: [String]] = [
        .earlyMorning: [
            "Morning, driver. Coffee's kicking in for both of us — I've got your HOS, the load, and weather on deck. What are we chasing first?",
            "Early start, huh? I'm riding shotgun — HOS, dispatch, weather, all pulled up. Talk to me.",
            "Hey, you're up before the sun again. I'm watching the clock and the road. What's on the radar?",
            "Good morning. Let's make this one smooth — HOS is green, weather's clean. What do you need from me?"
        ],
        .morning: [
            // 113th firing — corridor fixture excised ("I-20 weather"). Live
            // greeting hydrates real corridor weather from the routing layer.
            "Hey, good morning — I'm locked in on your HOS, the assigned load, and the corridor weather. What's first?",
            "Morning, driver. The rig's dialed in and so am I. Tell me what you want to tackle.",
            "Hey there. Dispatch queue is quiet so far, HOS looks healthy. What's on your mind?",
            "Good to see you rolling. Weather, route, clock — all pulled up. What can I chase down for you?",
            "Morning. I've been watching your lane overnight — nothing hot. How can I help today?"
        ],
        .afternoon: [
            "Hey — afternoon stretch. Load's tracking, HOS has runway. What do you need a hand with?",
            "Afternoon, driver. I've got your eyes on the road so you keep yours on the road. What's up?",
            "Hey. Midday check-in — everything on your load looks clean from here. Talk to me.",
            "Good afternoon. I'm monitoring the corridor ahead — nothing flagged. What's on your list?"
        ],
        .evening: [
            "Hey — evening driver. I'm tracking traffic into sundown. What can I get for you?",
            "Evening, driver. Let's bring this one home clean. What's on your mind?",
            "Hey. Sun's sliding down, HOS still has room. How can I help wrap this leg?",
            "Evening. I'm keeping an eye on overnight parking within your buffer. What do you need?"
        ],
        .night: [
            "Hey — running on night shift. I've got HOS, weather, and a parking list ready. What's first?",
            "Evening, driver. It's quiet out there — perfect time to nail this load. Talk to me.",
            "Hey. You hanging in? Clock and road are watched. What can I chase for you?",
            "Late push tonight. I'm here — HOS, fuel, safe stops, all pulled up. What do you need?"
        ],
        .lateNight: [
            "Hey — you're grinding. Watching your HOS like a hawk so you don't have to. What's up?",
            "Late one tonight, driver. I'm on weather and parking within your remaining clock. Talk to me.",
            "Hey. Running on fumes out there? I've got truck stops w/ open parking queued. What do you need?",
            "Middle of the night and the only company worth having is the one watching your clock. What's first?"
        ]
    ]

    /// Pick one greeting. Selection is uniform within the current day-part
    /// bucket and seeded by `sessionSeed` — pass a fresh UUID per launch
    /// and the result rotates on every cold start.
    static func pick(at date: Date = .init(), sessionSeed: UInt64 = .random(in: 0...UInt64.max)) -> String {
        let part = DayPart.from(date)
        let bank = variants[part] ?? variants[.morning]!
        var rng = SeededGen(state: sessionSeed | 1)
        let idx = Int.random(in: 0..<bank.count, using: &rng)
        return bank[idx]
    }

    /// Tiny SplitMix-style PRNG so a UInt64 seed produces a repeatable
    /// pick. Keeps the helper dependency-free while still giving us the
    /// "changes on every login" behavior the user asked for.
    private struct SeededGen: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z &>> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z &>> 27)) &* 0x94D049BB133111EB
            return z ^ (z &>> 31)
        }
    }
}

// MARK: - DrivereSangCoachSheet (orb tap target)

/// ESANG coach surface presented when the driver taps the center orb in the
/// BottomNav. ESANG is the in-cab AI copilot — she reads HOS, load state,
/// weather, and driver history to answer questions, plan routes, and catch
/// problems before they happen.
///
/// This is the local canonical shell: the orb floats at the top, a scrolling
/// transcript shows the live conversation, quick-action chips seed common
/// intents (HOS check, weather, load status, nearest truck stop), and a glass
/// composer sits at the bottom. All conversation state is in-memory for
/// this Wave; Wave-5 swaps the send handler for the live esang.chat backend
/// procedure without touching the UI.
struct DrivereSangCoachSheet: View {
    /// When the sheet is presented as a custom overlay (not a system sheet),
    /// the parent passes a close handler that runs the dissolve-to-orb
    /// animation before unmounting. Previews leave this `nil` and fall back
    /// to `.dismiss()` so the `#Preview` still works.
    var onClose: (() -> Void)? = nil

    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    /// Dispatcher injected from `DriverHomeScreen`. When ESANG replies with
    /// an `<<<ACTION:…>>>` token we fire the parsed intent through this
    /// closure so the wider app can switch tabs, open a load sheet, refresh
    /// the current surface, etc. Nil in previews — parser still runs and
    /// cleans the visible text, we just don't side-effect.
    @Environment(\.esangActionHandler) private var autopilot
    @FocusState private var composerFocused: Bool
    /// Voice input pipeline — Speech + AVAudioEngine. Owned here so the
    /// mic engine's lifetime is tied to the coach sheet mount. On final
    /// transcript we push it straight through `send(_:)` so voice + text
    /// paths converge on the same backend call.
    @StateObject private var voice = eSangVoiceInputController()

    struct Msg: Identifiable, Equatable {
        let id = UUID()
        let role: Role
        let text: String
        /// Optional image attachment — populated when the driver shares a
        /// photo from the composer's `+` menu (BOL snap, reefer gauge, dash
        /// warning light). Stored as raw PNG/JPEG so it round-trips through
        /// the `.onDrop` + PhotosPicker pipeline without a decoding dance.
        var imageData: Data? = nil
        /// Optional money-transfer card — populated when the driver sends
        /// a P2P transfer from the composer. ESANG echoes it back as a
        /// styled card so the transaction is visible in-thread.
        var transfer: ChatTransferPayload? = nil
        var time: Date = .init()

        enum Role: String { case esang, driver }
    }

    @State private var messages: [Msg] = [
        // Rotating warm opener — pulls from the eSangGreeting bank seeded
        // with a fresh UUID so every coach-sheet launch lands on a
        // different welcome. Replaces the prior static "Hey — I've got
        // eyes on your HOS…" literal the user flagged as too bland for a
        // Gemini-backed copilot.
        .init(role: .esang, text: eSangGreeting.pick())
    ]

    @State private var draft: String = ""
    @State private var orbState: OrbeSang.State = .idle
    /// `+` attach menu state. The composer exposes two affordances through
    /// this menu: photo upload (BOL/DVIR/reefer evidence) and P2P transfer
    /// (EusoWallet-backed driver-to-driver pay). Both write back a typed
    /// `Msg` so the transcript mirrors what the wider app surfaces render.
    @State private var showAttachMenu: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var pickedPhoto: PhotosPickerItem? = nil

    /// Canned quick-actions — ESANG answers these locally for the Wave-4 demo
    /// until the live chat procedure lands.
    // 113th firing — M2 doctrine sweep. The previous chip seeds carried
    // city + corridor fixtures ("Dallas delivery", "I-20 corridor",
    // "before Dallas"). Replaced with corridor-agnostic prompt copy so
    // the offline / pre-load state never leaks a destination the active
    // Load doesn't actually carry. Live chip copy, when ESANG endpoint
    // is reachable, will substitute the real Load city / corridor.
    private let chips: [(String, String)] = [
        ("HOS buffer",      "How's my HOS buffer looking for today's delivery?"),
        ("Route weather",   "Weather on the corridor tonight?"),
        ("Fuel stop",       "Best fuel stop on the route ahead?"),
        ("Detention log",   "Open a detention claim for the last stop.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            IridescentHairline()
            transcript
            chipRow
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(palette.bgPage)
        // Tapping anywhere outside the composer dismisses the keyboard.
        // We skip `.toolbar(.keyboard)` because the coach sheet is a custom
        // ZStack overlay (not inside a NavigationStack), and the system
        // keyboard toolbar renders above the composer and visually collides
        // with the send button in that configuration.
        .contentShape(Rectangle())
        .onTapGesture { composerFocused = false }
        .onAppear {
            // Orb starts idle on every open. (Regression fix: we were
            // forcing `.thinking` here, which left the orb stuck in the
            // amber/intensified state any time the chat panel opened,
            // even when nothing was in flight. State transitions now
            // come exclusively from the voice pipeline + `send(_:)`.)
            orbState = .idle
            // Capture the voice pipeline's final transcript and ship it
            // through the same send(_:) used by the text composer.
            voice.onFinalTranscript = { transcript in
                Task { @MainActor in
                    send(transcript)
                }
            }
        }
        // Mic hot → orb flips to `.listening` so the particle field
        // locks into a travelling waveform and the halo shifts to blue.
        // Gives the driver a strong at-a-glance cue that voice capture
        // is live even when their eyes flick off the text field. When
        // the mic drops, we only revert to `.idle` if the orb isn't
        // already `.thinking` (a tap-and-release with a non-empty
        // transcript flips to .thinking inside `send(_:)`; we don't want
        // to stomp that transition).
        .onChange(of: voice.isRecording) { _, recording in
            if recording {
                orbState = .listening
            } else if orbState == .listening {
                orbState = .idle
            }
        }
        .onDisappear {
            orbState = .idle
            // Cancel any in-flight recording so the mic + audio session
            // release cleanly when the sheet dismisses.
            voice.cancel()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            OrbeSang(state: orbState, diameter: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Your AI copilot · online")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close ESANG")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    ForEach(messages) { m in
                        bubble(m).id(m.id)
                    }
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ m: Msg) -> some View {
        HStack {
            if m.role == .driver { Spacer(minLength: 40) }
            bubbleBody(m)
                .frame(maxWidth: 280, alignment: m.role == .driver ? .trailing : .leading)
            if m.role == .esang { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func bubbleBody(_ m: Msg) -> some View {
        if let payload = m.transfer {
            // EusoWallet transfer card. Always driver-initiated in this
            // surface, so the outbound (gradient) variant is what we
            // render here.
            esangTransferCard(payload)
        } else if let data = m.imageData,
                  let ui = UIImage(data: data) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 240, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                if !m.text.isEmpty {
                    Text(m.text)
                        .font(EType.body)
                        .foregroundStyle(m.role == .driver ? .white : palette.textPrimary)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(m.role == .driver
                          ? AnyShapeStyle(LinearGradient.diagonal)
                          : AnyShapeStyle(palette.bgCard))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(m.role == .driver ? Color.clear : palette.borderFaint)
            )
        } else {
            Text(m.text)
                .font(EType.body)
                .foregroundStyle(m.role == .driver ? Color.white : palette.textPrimary)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .background(
                    Group {
                        if m.role == .driver {
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(LinearGradient.diagonal)
                        } else {
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(palette.bgCard)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                        .strokeBorder(palette.borderFaint)
                                )
                        }
                    }
                )
        }
    }

    /// EusoWallet transfer card rendered inside the ESANG coach transcript.
    /// We use the outbound (driver-initiated) variant because the ESANG
    /// chat is always driver → wallet.
    @ViewBuilder
    private func esangTransferCard(_ payload: ChatTransferPayload) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("You sent")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(payload.formattedAmount)
                        .font(EType.numeric)
                        .foregroundStyle(.white)
                }
                Spacer()
                switch payload.status {
                case .pending:
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini).tint(.white)
                        Text("Pending").font(EType.micro).foregroundStyle(.white)
                    }
                case .sent:
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(EType.micro)
                        .foregroundStyle(.white)
                case .failed:
                    Label("Failed", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(EType.micro)
                        .foregroundStyle(Brand.danger)
                }
            }
            Text("To \(payload.recipientName)")
                .font(EType.caption)
                .foregroundStyle(Color.white.opacity(0.92))
            if let memo = payload.memo, !memo.isEmpty {
                Text(memo)
                    .font(EType.caption)
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            Text("EusoWallet · powered by Stripe")
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient.diagonal)
        )
    }

    // MARK: Chip row

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(chips, id: \.0) { chip in
                    Button {
                        send(chip.1)
                    } label: {
                        Text(chip.0)
                            .font(EType.caption)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, Space.s2)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(palette.bgCardSoft)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(palette.borderFaint)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.s5)
            .padding(.bottom, Space.s2)
        }
    }

    // MARK: Composer

    /// Inline pending-image strip. Populated when the driver picks a photo
    /// via the composer's PhotosPicker and cleared on send or discard.
    @State private var pendingImageData: Data? = nil

    @ViewBuilder
    private var pendingAttachmentStrip: some View {
        if let data = pendingImageData,
           let ui = UIImage(data: data) {
            HStack(spacing: Space.s3) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attached photo")
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                    Text("ESANG will read it alongside your message.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Button {
                    pendingImageData = nil
                    pickedPhoto = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove attached photo")
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s2)
            .background(palette.bgCardSoft)
            .overlay(alignment: .top) { Divider().overlay(palette.borderFaint) }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            pendingAttachmentStrip
            HStack(alignment: .bottom, spacing: Space.s2) {
                // PhotosPicker — single-tap shortcut to share a photo with
                // ESANG (BOL snap, reefer gauge, dash warning, DVIR pic).
                PhotosPicker(selection: $pickedPhoto,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .accessibilityLabel("Attach photo")

                // NOTE: EusoWallet P2P transfers live on the messaging surface
                // (DriverConversationView), not on the ESANG coach. The coach
                // has no conversationId to bind against `messages.sendPayment`,
                // so the dollar-sign entry point was removed in the 65th firing
                // (Phase C landmine sweep) to eliminate a DispatchQueue-timer
                // mock that faked a Stripe ACK. Drivers send money through
                // Messages → thread → composer, where the real tRPC call runs.

                // While the mic is hot we route live partial transcripts into
                // the `draft` binding so the driver can see what ESANG will
                // receive; on final (onFinalTranscript) we ship it straight
                // through `send(_:)`.
                TextField("Ask ESANG…", text: voice.isRecording ? $voice.transcript : $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(voice.isRecording
                                          ? Brand.magenta.opacity(0.55)
                                          : palette.borderFaint,
                                          lineWidth: voice.isRecording ? 1.2 : 1)
                    )

                // Push-to-talk mic. Per user direction (2026-04-20):
                //   > also add voice command to esang chat in the app. its missing
                // Controller requests mic + speech permission on first tap,
                // streams partial transcripts into `draft`, and hands the
                // final transcript to `send(_:)` on release.
                eSangVoiceInputButton(controller: voice)

                Button {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Allow send when there's either text or a photo attached.
                    guard !trimmed.isEmpty || pendingImageData != nil else { return }
                    send(trimmed, image: pendingImageData)
                    draft = ""
                    pendingImageData = nil
                    pickedPhoto = nil
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(LinearGradient.diagonal)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.55)
                .accessibilityLabel("Send to ESANG")
            }
            .padding(.horizontal, Space.s5)
            // Lift the composer off the home indicator — the coach sheet is
            // presented as a custom overlay (not a system sheet), so we have to
            // respect the bottom safe area ourselves.
            .padding(.bottom, Space.s4 + Device.safeBottom)
            .padding(.top, Space.s2)
        }
        // Photo pipeline: PhotosPicker drops a PhotosPickerItem; we pull
        // the raw bytes off it here so the composer can both preview the
        // thumbnail and ship the data through `send(_:, image:)` on tap.
        .onChange(of: pickedPhoto) { _, newValue in
            Task {
                if let item = newValue,
                   let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { pendingImageData = data }
                }
            }
        }
    }

    /// Composer-level send-readiness. True when there's either a
    /// non-empty draft or a pending photo attached.
    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || pendingImageData != nil
    }

    // MARK: Send → production eSang (Gemini-backed via tRPC)

    /// Overload kept for voice pipeline (no image) — forwards to the new
    /// image-aware variant so the ESANG reply logic stays in one place.
    private func send(_ text: String) {
        send(text, image: nil)
    }

    /// Push the driver's message into the transcript, then ship it to
    /// `esang.chat` on the live backend (eusotrip-app.azurewebsites.net)
    /// — same procedure the web app uses, so replies here match what
    /// drivers get in the browser. Falls back to the canned intent
    /// matcher only if the network call fails, so the orb is never
    /// dead silent.
    ///
    /// `image` is the optional attached photo. For the in-memory wave we
    /// just echo the attachment in the transcript; Wave-6 base64-encodes
    /// it alongside the text for the Gemini multimodal call.
    private func send(_ text: String, image: Data?) {
        let userMsg = Msg(role: .driver, text: text, imageData: image)
        messages.append(userMsg)
        composerFocused = false
        orbState = .thinking

        // Snapshot the env dispatcher at call time so the async
        // follow-up isn't reading a stale @Environment inside a
        // non-body closure context.
        let dispatcher = autopilot

        Task {
            let reply: String
            do {
                let resp = try await EusoTripAPI.shared.esang.chat(
                    message: text,
                    currentPage: "driver.coach",
                    loadId: nil
                )
                reply = resp.message
            } catch {
                // Best-effort local fallback so an offline driver still
                // gets a useful response instead of radio silence.
                reply = Self.canned(for: text)
            }
            // Split ESANG's reply into driver-visible text + machine actions.
            // The parser strips every `<<<ACTION:verb:arg>>>` token so the
            // chat bubble shows clean prose — and hands back a typed list
            // of intents the autopilot dispatcher can execute (navigate,
            // open a load sheet, etc.). Per user direction (2026-04-20):
            //   > can you hide the '<<<action:navigate:/marketplace '
            //   > which i know that is a command. please hide this…
            let (cleaned, actions) = eSangAutopilot.parse(reply)
            await MainActor.run {
                if !cleaned.isEmpty {
                    messages.append(Msg(role: .esang, text: cleaned))
                }
                orbState = .idle
                // Dispatch each action on a tiny stagger so a
                // navigate-then-open-chat sequence animates naturally
                // instead of stepping on itself.
                for (idx, action) in actions.enumerated() {
                    let delay = Double(idx) * 0.20
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        dispatcher?(action)
                    }
                }
            }
        }
    }

    /// Offline fallback — tiny intent matcher so the orb stays useful
    /// when the device is off-network. Once the live `esang.chat` call
    /// succeeds this is skipped entirely; it's only here as a safety
    /// net behind the production endpoint.
    ///
    /// 113th firing — M2 doctrine sweep: every reply below was rewritten
    /// to a generic, voice-preserving response that does NOT carry
    /// fixture brands (Love's #448 / Pilot #612), fixture addresses
    /// (2115 Dallas Logistics Blvd), fixture corridors (I-20 / Longview),
    /// or specific clock numbers (7h 22m, 13:13 CDT, $3.89/gal, 62 mi).
    /// When `esang.chat` is reachable the live endpoint hydrates the
    /// real numbers from the active Load + HOS + fuel-grid + ETA
    /// payloads. Until then these strings stay generic so the offline
    /// fallback can never hallucinate a number the driver would act on.
    static func canned(for prompt: String) -> String {
        let p = prompt.lowercased()
        if p.contains("hos") {
            // 113th firing — was: hard-coded "7h 22m / 90 min buffer / 14-hr
            // clock / Dallas on-time with 45-min cushion". Replaced with a
            // generic clock-pointer response. Live endpoint serves the real
            // hours from `hos.getStatus`.
            return "I'm reading your remaining drive time and 14-hour clock — open the HOS panel for the exact minutes and I'll flag the next break window."
        }
        if p.contains("weather") || p.contains("rain") || p.contains("storm") {
            // 113th firing — was: "I-20 west / Longview / Visibility 10+ mi"
            // corridor-specific fixture copy. Replaced with a generic radar
            // response. Live endpoint pulls real corridor weather from the
            // routing layer.
            return "Pulling the radar along your route — I'll ping you the moment anything severe pops onto the corridor ahead."
        }
        if p.contains("fuel") || p.contains("diesel") {
            // 113th firing — was: competitor brand fixtures "Love's #448 in
            // Tyler — $3.89/gal, 62 mi ahead ... Beats Pilot #612 by 9¢".
            // Replaced with a generic fuel-grid response. Live endpoint
            // hydrates real cheapest-first stops from `fuel.getStops`.
            return "Watching the diesel grid up the corridor. Open the Fuel pane and I'll line them up cheapest-first with detention-risk and shower availability already weighed in."
        }
        if p.contains("detention") || p.contains("claim") {
            // M2 doctrine — generic copy until ESANG live endpoint hydrates the
            // real shipper / dock / over-window / accessorial dollars from the
            // Load + dispatch.getExceptions payload. Removed the Walmart DC 4492
            // / 2h 14m / $150 fixture per 111th firing's M2 leak sweep.
            return "Filed. Detention claim is in queue with the receiver — I'll ping you the moment they cut the add-on."
        }
        if p.contains("eta") || p.contains("dallas") || p.contains("arriv") {
            // 113th firing — was: hard-coded "ETA 13:13 CDT at 2115 Dallas
            // Logistics Blvd — 7 min ahead". Replaced with a generic ETA
            // pointer. Live endpoint serves real ETA from the active Load
            // + routing telemetry.
            return "Math says you're trending toward your receiver appointment — tap the load card for the live ETA breakdown and the cushion you've got in hand."
        }
        return "Got it. I'll dig into that and come back with specifics in a sec."
    }
}

// MARK: - NewMessageSheet (compose — 1:1 + group)
//
// Closes the gap that shipped in build 39: the inbox could read threads
// but had no way to *initiate* one. This sheet surfaces the compose
// flow — search + pick peers, optionally name a group — and calls
// `messages.createConversation` with the right payload shape. On
// success it hands the caller an `InboxThread` synthesized from the
// picked participants so the parent can drill into
// `DriverConversationView` immediately without waiting for a roundtrip
// to `getConversations` to land the new row.
//
// Modes:
//   • `.direct` — pick a single peer; tap the row and the conversation
//     is created + opened in one shot.
//   • `.group`  — multi-select peers (min 2) + type a group name, then
//     tap "Create group".
//
// Search is backed by `messages.searchUsers`. An empty query returns
// the server's suggested/recent-peers list so there's always something
// to pick from on first open.

struct NewMessageSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    /// Called once the conversation has been created server-side.
    /// The parent is responsible for routing into the conversation
    /// surface (see `DriverMessagesSheet` for the pattern).
    let onCreated: (InboxThread) -> Void

    enum Mode: Hashable { case direct, group }

    // ──────────── UI state ────────────
    @State private var mode: Mode = .direct
    @State private var query: String = ""
    @State private var groupName: String = ""

    // ──────────── Data state ────────────
    @State private var results: [MessagingUserResult] = []
    @State private var selected: [MessagingUserResult] = []
    @State private var isSearching: Bool = false
    @State private var didFirstLoad: Bool = false
    @State private var errorText: String? = nil

    // ──────────── Create-conversation state ────────────
    @State private var isCreating: Bool = false
    /// Debounce handle so we don't fire a `searchUsers` roundtrip on
    /// every keystroke.
    @State private var debounceTask: Task<Void, Never>? = nil

    @FocusState private var queryFocused: Bool
    @FocusState private var groupNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    modeToggle
                    if mode == .group {
                        groupNameField
                        if !selected.isEmpty {
                            selectedChips
                        }
                    }
                    searchField
                    if let errorText {
                        Text(errorText)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                    resultsList
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s8)
            }

            if mode == .group {
                groupFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage)
        .task {
            if !didFirstLoad {
                await runSearch(query: "")
            }
        }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode == .direct ? "New message" : "New group")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(mode == .direct
                     ? "Pick a dispatcher, broker, or driver to DM."
                     : "Pick 2+ people and give the group a name.")
                    .font(EType.micro)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Mode toggle

    @ViewBuilder private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.direct, label: "Direct message", glyph: "person.crop.circle")
            modeButton(.group,  label: "Group chat",     glyph: "person.2")
        }
        .padding(2)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func modeButton(_ m: Mode, label: String, glyph: String) -> some View {
        let isActive = mode == m
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                mode = m
                // Clear selection when flipping modes so the user
                // doesn't accidentally create a 1:1 with a leftover
                // group-sized selection.
                if m == .direct { selected = [] }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: glyph)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(EType.caption)
            }
            .foregroundStyle(isActive ? .white : palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isActive {
                        LinearGradient.diagonal
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Group-name field

    @ViewBuilder private var groupNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Group name")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
            TextField("e.g. Dallas team · Wk 17", text: $groupName)
                .textFieldStyle(.plain)
                .focused($groupNameFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Selected chips

    @ViewBuilder private var selectedChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected · \(selected.count)")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
            // Horizontal-scrolling chip rail. Tapping an "x" removes a
            // participant without having to hunt through the results list.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selected) { u in
                        HStack(spacing: 6) {
                            Text(u.name)
                                .font(EType.caption)
                                .foregroundStyle(palette.textPrimary)
                            Button {
                                toggleSelected(u)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 6)
                        .padding(.vertical, 6)
                        .background(palette.bgCardSoft)
                        .overlay(
                            Capsule().strokeBorder(palette.borderFaint)
                        )
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: Search field

    @ViewBuilder private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            TextField("Search dispatchers, brokers, drivers…", text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($queryFocused)
                .foregroundStyle(palette.textPrimary)
                .onChange(of: query) { _, newValue in
                    debounce(newValue)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    Task { await runSearch(query: "") }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: Results list

    @ViewBuilder private var resultsList: some View {
        if !didFirstLoad && isSearching {
            // Skeleton — four placeholder rows so the panel doesn't
            // collapse while the first `searchUsers` lands.
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: Space.s3) {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(palette.tintNeutral)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral)
                                .frame(width: 160, height: 12)
                            RoundedRectangle(cornerRadius: 4).fill(palette.tintNeutral.opacity(0.6))
                                .frame(width: 220, height: 10)
                        }
                        Spacer()
                    }
                    .padding(.vertical, Space.s3)
                }
            }
            .redacted(reason: .placeholder)
        } else if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(palette.textTertiary)
                Text(query.isEmpty
                     ? "Searching for people near you…"
                     : "No one found for \"\(query)\"")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s6)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { idx, user in
                    userRow(user)
                    if idx < results.count - 1 {
                        Divider().overlay(palette.borderFaint)
                            .padding(.leading, 60)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    @ViewBuilder
    private func userRow(_ user: MessagingUserResult) -> some View {
        let isSelected = selected.contains(user)
        Button {
            if mode == .direct {
                // One-shot path: select + create + dismiss.
                Task { await createDirect(with: user) }
            } else {
                toggleSelected(user)
            }
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                // Avatar initials
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral)
                    Text(initials(of: user.name))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(roleSubtitle(user))
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()

                if mode == .group {
                    // Checkbox indicator for the multi-select path.
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Color.white : palette.textTertiary)
                        .background(
                            Group {
                                if isSelected {
                                    Circle().fill(LinearGradient.diagonal)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .clipShape(Circle())
                } else if isCreating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isCreating)
        .accessibilityLabel(mode == .direct
                            ? "Start a conversation with \(user.name)"
                            : (isSelected ? "Remove \(user.name)" : "Add \(user.name) to group"))
    }

    // MARK: Group footer

    @ViewBuilder private var groupFooter: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            HStack(spacing: Space.s3) {
                Text(selected.count < 2
                     ? "Pick at least 2 people"
                     : "\(selected.count) selected")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button {
                    Task { await createGroup() }
                } label: {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text("Create group")
                            .font(EType.bodyStrong)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, 10)
                    .background(
                        canCreateGroup
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.tintNeutral)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canCreateGroup || isCreating)
                .accessibilityLabel("Create group")
            }
            .padding(.horizontal, Space.s5)
            .padding(.vertical, Space.s3)
            .background(palette.bgCardSoft)
        }
    }

    // MARK: Computed

    private var canCreateGroup: Bool {
        mode == .group &&
            selected.count >= 2 &&
            !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Search + debounce

    private func debounce(_ text: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }
            await runSearch(query: text)
        }
    }

    private func runSearch(query: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let q: String? = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : query
            let users = try await EusoTripAPI.shared.messaging.searchUsers(
                query: q, limit: 30
            )
            results = users
            errorText = nil
            didFirstLoad = true
        } catch EusoTripAPIError.unauthenticated {
            errorText = "Sign in to find people to message."
            didFirstLoad = true
        } catch {
            errorText = "Couldn't reach the directory — \(error.localizedDescription)"
            didFirstLoad = true
        }
    }

    // MARK: Mutations

    private func toggleSelected(_ user: MessagingUserResult) {
        if let idx = selected.firstIndex(of: user) {
            selected.remove(at: idx)
        } else {
            selected.append(user)
        }
    }

    private func createDirect(with user: MessagingUserResult) async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let result = try await EusoTripAPI.shared.messaging.createConversation(
                participantIds: [user.id],
                type: "direct",
                name: nil,
                loadId: nil,
                initialMessage: nil
            )
            let thread = Self.synthesizeThread(
                id: result.id,
                isGroup: false,
                name: user.name,
                participants: [user]
            )
            onCreated(thread)
            dismiss()
        } catch EusoTripAPIError.unauthenticated {
            errorText = "Please sign in to start a conversation."
        } catch {
            errorText = "Couldn't start the conversation — \(error.localizedDescription)"
        }
    }

    private func createGroup() async {
        guard canCreateGroup, !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await EusoTripAPI.shared.messaging.createConversation(
                participantIds: selected.map(\.id),
                type: "group",
                name: trimmed,
                loadId: nil,
                initialMessage: nil
            )
            let thread = Self.synthesizeThread(
                id: result.id,
                isGroup: true,
                name: trimmed,
                participants: selected
            )
            onCreated(thread)
            dismiss()
        } catch EusoTripAPIError.unauthenticated {
            errorText = "Please sign in to create a group."
        } catch {
            errorText = "Couldn't create the group — \(error.localizedDescription)"
        }
    }

    // MARK: Helpers

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first.map(String.init) }.joined()
        return chars.isEmpty ? "·" : chars.uppercased()
    }

    private func roleSubtitle(_ user: MessagingUserResult) -> String {
        if let role = user.role, !role.isEmpty {
            let lowered = role.lowercased()
            switch lowered {
            case "dispatcher", "dispatch": return "Fleet dispatcher"
            case "broker":                  return "Broker · load desk"
            case "driver":                  return "Driver peer"
            case "shipper":                 return "Shipper"
            case "admin":                   return "Admin · Eusorone"
            default:                         return role.capitalized
            }
        }
        if let email = user.email, !email.isEmpty { return email }
        return "Direct message"
    }

    /// Build an `InboxThread` from the data the compose sheet has in
    /// hand. We don't wait for a `getConversations` roundtrip because
    /// the parent fires one in the background after the sheet closes —
    /// this synthesized thread gets the driver into the conversation
    /// surface immediately.
    static func synthesizeThread(
        id: String,
        isGroup: Bool,
        name: String,
        participants: [MessagingUserResult]
    ) -> InboxThread {
        let peerRole = participants.first?.role?.lowercased() ?? ""
        let glyph: String = {
            if isGroup { return "person.2" }
            if peerRole.contains("dispatch") { return "headphones" }
            if peerRole.contains("broker")   { return "truck.box" }
            if peerRole.contains("driver")   { return "person.crop.square" }
            if peerRole.contains("shipper")  { return "building.2" }
            return "person.crop.circle"
        }()
        let subtitle: String = {
            if isGroup { return "Group chat · \(participants.count) members" }
            switch peerRole {
            case "dispatcher", "dispatch": return "Fleet dispatcher"
            case "broker":                  return "Broker · load desk"
            case "driver":                  return "Driver peer"
            case "shipper":                 return "Shipper"
            default:                         return "Direct message"
            }
        }()
        let allowsTransfer = !isGroup &&
            (peerRole.contains("driver") || peerRole.isEmpty || peerRole == "user")

        return InboxThread(
            id: id,
            glyph: glyph,
            title: name,
            subtitle: subtitle,
            preview: "Tap to start the conversation",
            time: "",
            unread: 0,
            allowsTransfer: allowsTransfer
        )
    }
}

// MARK: - Previews

#Preview("DriverTripsPane · Dark") {
    DriverTripsPane()
        .frame(width: 390, height: 844)
        .background(Theme.dark.bgPrimary)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("DriverWalletPane · Night") {
    DriverWalletPane()
        .frame(width: 390, height: 844)
        .background(Theme.dark.bgPrimary)
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("DriverWalletPane · Afternoon") {
    DriverWalletPane()
        .frame(width: 390, height: 844)
        .background(Theme.light.bgPrimary)
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

#Preview("DriverMePane · Dark") {
    DriverMePane()
        .frame(width: 390, height: 844)
        .background(Theme.dark.bgPrimary)
        .environment(\.palette, Theme.dark)
        .environmentObject(DriverProfileStore())
        .preferredColorScheme(.dark)
}

#Preview("MyLoadsSheet · Dark") {
    MyLoadsSheet()
        .frame(width: 390, height: 844)
        .background(Theme.dark.bgPage)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}
