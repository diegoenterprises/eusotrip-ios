//
//  010_DriverHome.swift
//  EusoTrip — LIVE production screen (A→Z, screen 010)
//
//  Pulls real data from the EusoTrip tRPC backend via EusoTripAPI:
//    • loads.search(status: "assigned", limit: 1)
//    • hos.getStatus()
//    • loads.getById(<id>)   (hydrates pickup/delivery detail)
//
//  Preserves doctrine:
//    §2 nav + orb invariants, §3 numbers-first copy, §4.3 iridescent hairline,
//    §7 breathe density, §8 Driver rhythm (ActiveCard + 2 metrics + list),
//    §12 DONE criteria.
//
//  Twin of:  02_html/dark/010_driver_home.html
//            02_html/light/010_driver_home.html
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Screen

struct DriverHome: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var profile: DriverProfileStore
    @StateObject private var vm = DriverHomeViewModel()
    /// Sheet→push detail layer (push-nav mandate, 2026-06-09 / audit
    /// M25). The active-load "Review load brief" CTA and the suggested-
    /// loads carousel push the canonical `LoadDetailSheet` in-stack via
    /// the Driver surface's `RoleDetailLayer`; the legacy `.sheet`
    /// presenters stay as the nil-env fallback (previews).
    @Environment(\.rolePushDetail) private var pushDetail
    @State private var showMessages: Bool = false
    /// True when the driver has tapped the active-load card's "Details"
    /// button. Presents `LoadDetailSheet` over the Home surface with the
    /// same rich load/route/broker detail as the Eusoboards flow. Wired
    /// per user direction (2026-04-20):
    ///
    ///   > same thing for this screen when you click on details
    @State private var showAssignedLoadDetail: Bool = false
    /// Presents the full HOS Duty Status surface (019_HosDutyStatus) over
    /// Home when the driver taps the HOS DRIVE LEFT metric tile. Wired per
    /// user direction (2026-04-20):
    ///
    ///   > clicking on hos should take you to your hos port screen with
    ///   > HOS data and meters per the figma
    @State private var showHosSheet: Bool = false
    /// Presents the full EusoWallet (DriverWalletPane) surface over Home
    /// when the driver taps the WALLET AVAILABLE metric tile. Wired per
    /// user direction (2026-04-20):
    ///
    ///   > clicking on wallet available should take you to eusowallet
    @State private var showWalletSheet: Bool = false
    /// Selected `AvailableLoad` from the home carousel of suggested
    /// freight shown when the driver is between loads. Drives
    /// `LoadDetailSheet` so tapping a card surfaces the same rich detail
    /// (route · permits · rate breakdown · broker) the Eusoboards
    /// surface renders. Wired per user direction (2026-04-21):
    ///
    ///   > that module should be a carousel of available loads and
    ///   > when you press it it takes you to the load details when you
    ///   > arent in an active load.
    @State private var selectedSuggestedLoad: AvailableLoad? = nil
    /// Presents the notifications inbox sheet over Home when the
    /// `NotificationsWidget` tile is tapped (or any other surface posts
    /// `.eusoOpenNotificationsRequested`). Wraps the existing
    /// `MeNotificationsView` body so the inbox surface stays in sync
    /// with what the Me sub-route renders.
    @State private var showNotificationsSheet: Bool = false
    /// D-1 fallback presenter for the inbound truck-posting surface (113)
    /// when no push-nav detail layer is mounted (preview / isolated host).
    /// Production routes via `\.rolePushDetail` (in-stack push).
    @State private var showTruckPostingSheet: Bool = false

    // ── Home-widget customization (2026-05-23 founder ask) ──────
    // Migrated to shared HomeWidgetGrid + HomeWidgetCatalog
    // (defined at file scope above). This struct just declares the
    // canonical slot order + the render mapping for this role's
    // tiles. The grid handles edit mode, drag/drop, RESET, hydrate
    // / persist via users.saveDashboardLayout("DRIVER", …),
    // reconciliation, and the UserDefaults offline cache.
    private let widgetLayoutKey = "driver.home.widgetOrder"
    private let driverHomeCanonicalOrder: [String] = [
        "current_route", "esang", "next_delivery", "hos_tracker", "earnings_summary", "weather_alerts",
        "messages", "notifications", "haul", "compliance", "news", "recent", "hotZones",
        "near_me_intel",
        "performance_score", "vehicle_health", "mileage_tracker", "fuel_economy",
        "wallet_activity", "fuel_stations", "rest_areas",
    ]

    /// Maps a catalog widget id → the concrete iOS tile view this
    /// driver-home wires today. Future widget ports just add a case;
    /// the grid + catalog handle the rest.
    private func driverHomeRender(_ id: String) -> AnyView {
        switch id {
        case "current_route":   AnyView(currentWorkWidget)
        case "esang":           AnyView(eSangMorningBriefCard())
        case "next_delivery":   AnyView(NextDeliveryWidget(summary: vm.activeLoadSummary))
        case "hos_tracker":     AnyView(hosHomeWidget)
        case "earnings_summary":AnyView(EarningsSummaryWidget(available: vm.walletAvailable, availableDisplay: vm.walletAvailableDisplay))
        case "weather_alerts":  AnyView(WeatherAlertsWidget(snapshot: vm.weather, lane: vm.laneWeather))
        // Cross-platform layouts saved on web can carry the universal
        // "weather" tile — render the real card (compact at half span)
        // instead of silently dropping the slot to EmptyView.
        case "weather":         AnyView(WeatherTileWidget(snapshot: vm.weather, lane: vm.laneWeather))
        case "messages":        AnyView(MessagesWidget())
        case "notifications":   AnyView(NotificationsWidget())
        case "haul":            AnyView(TheHaulWeeklyTile())
        case "compliance":      AnyView(ComplianceCountdownStrip())
        case "news":            AnyView(NewsCarouselWidget())
        case "recent":          AnyView(recentSection)
        case "hotZones":        AnyView(HotZonesWidget())
        case "near_me_intel":   AnyView(NearMeLoadIntelWidget())
        case "performance_score": AnyView(PerformanceScoreWidget())
        case "vehicle_health":  AnyView(VehicleHealthWidget())
        case "mileage_tracker": AnyView(MileageTrackerWidget(currentLoadMiles: vm.activeLoad?.distanceValue))
        case "fuel_economy":    AnyView(FuelEconomyWidget())
        case "wallet_activity": AnyView(WalletActivityWidget())
        case "fuel_stations":   AnyView(FuelStationsWidget())
        case "rest_areas":      AnyView(RestAreasWidget())
        default:                AnyView(EmptyView())
        }
    }

    /// Live suggestions feed — `loads.search(status:"available")` via
    /// `LoadBoardStore`. Every seeded `[AvailableLoad]` literal that
    /// used to live here (PACCO, ColdChain, Sunbelt, Heartland, etc.)
    /// is gone — the store calls the real tRPC procedure and projects
    /// `[LoadSummary]` onto the existing `AvailableLoad` shape via
    /// `AvailableLoad.from(_:)` in the adapters file.
    @StateObject private var suggestedLoadsStore = LoadBoardStore()
    private var suggestedLoads: [AvailableLoad] {
        suggestedLoadsStore.items.map(AvailableLoad.from)
    }

    /// Greeting name — reads from the shared `DriverProfileStore` so the
    /// moment a driver saves a new first name in ProfileEditView the Home
    /// banner picks it up without a reload. Falls back to the VM's stored
    /// name (which is itself seeded from the auth payload) only while the
    /// profile store is still hydrating from UserDefaults on cold launch.
    private var greetingFirstName: String {
        let name = profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? vm.driverFirstName : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            // Home content wrapped in a ScrollView so `.refreshable`
            // binds to a live drag-down gesture. On shorter devices the
            // metric row + recent section also needs to scroll — the
            // previous flat VStack clipped everything below the fold.
            ScrollView {
                // StaggeredEntranceStack wraps Home's hero sections so each
                // one springs into place in source order (weather → active
                // card → metric row → recent section) with the iPhone-unlock
                // cascade — scale 0.92 + blur 5pt + 50 ms stagger — ONCE on
                // cold launch. Re-visits in the same session render settled
                // (first-load gate). Reduce-Motion → clean fade.
                StaggeredEntranceStack(alignment: .leading, spacing: Space.s5) {
                    HomeWidgetGrid(
                        canonicalOrder: driverHomeCanonicalOrder,
                        role: "DRIVER",
                        storageKey: widgetLayoutKey,
                        weather: {
                            AnyView(HomeWeatherWidget(
                                lane: vm.laneWeather,
                                onSnapshot: { vm.acceptLocalWeatherSnapshot($0) }
                            ))
                        },
                        render: { id in driverHomeRender(id) }
                    )

                    if vm.isOffline {
                        offlineBanner
                    }
                    if case .error(let message) = vm.phase {
                        errorState(message)
                    }
                    // Reserve clearance under the floating BottomNav
                    // pill so the recent section doesn't tuck behind it.
                    Color.clear
                        .frame(height: Device.navHeight + Device.safeBottom + Space.s4)
                }
                .padding(Space.s5)
                .animation(.easeOut(duration: 0.18), value: vm.phase)
            }
            .scrollIndicators(.hidden)
            // Drag-down refreshes the home dashboard — weather, active
            // load card, metric tiles, and recent section. `vm.load()`
            // is the same async loader used on first appearance, so the
            // refresh is a real reload, not a stub.
            .eusoRefreshable {
                await vm.load()
                await suggestedLoadsStore.refresh()
            }
        }
        .task {
            await vm.load()
            await suggestedLoadsStore.refresh()
        }
        // RealtimeService → live updates from the driver's load
        // assignments / reassignments / surface refresh events trigger
        // an immediate dashboard reload so a brand-new load shows up
        // without waiting for the next pull-to-refresh.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task {
                await vm.load()
                await suggestedLoadsStore.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task {
                await vm.load()
                await suggestedLoadsStore.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task {
                await vm.load()
                await suggestedLoadsStore.refresh()
            }
        }
        // Home-widget tap routing — closes the dead-tap gap on the
        // MessagesWidget + NotificationsWidget tiles (they fire these
        // names with no other local effect, so without a listener the
        // taps would be true dead-taps per the observability-vs-dead
        // doctrine).
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("eusoOpenMessagesRequested"))) { _ in
            showMessages = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("eusoOpenNotificationsRequested"))) { _ in
            showNotificationsSheet = true
        }
        // D-1 fallback: when the push-nav detail layer isn't mounted
        // (isolated host / preview) the post-truck CTA posts this name so
        // the surface still routes. Production always uses the in-stack
        // push and never fires this.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("eusoOpenTruckPostingRequested"))) { _ in
            showTruckPostingSheet = true
        }
        .fullScreenCover(isPresented: $showTruckPostingSheet) {
            NavigationStack {
                DriverTruckPosted()
                    .environment(\.palette, palette)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showTruckPostingSheet = false }
                        }
                    }
                    .navigationTitle("Post your truck")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        // Load Details sheet for the active/assigned load. Reuses the
        // canonical LoadDetailSheet the Eusoboards surface renders so
        // drivers get the same route map, rate breakdown, and broker
        // card regardless of which surface opened it.
        // LEGACY FALLBACK ONLY (push-nav mandate, 2026-06-09 / audit M25):
        // the production path is `openAssignedLoadDetail()` → in-stack
        // push via `RoleDetailLayer`. This slide-up presenter fires only
        // when no detail layer is mounted (previews / isolated hosting).
        .sheet(isPresented: $showAssignedLoadDetail) {
            assignedLoadDetailContent(hostedInPush: false)
                .eusoSheetX()
        }
        // HOS port — full 019 surface with banks / 24h timeline / 3-meter
        // strip. Picks the `.afternoon` register so the live status reads
        // as an in-shift break state instead of the night scenario.
        .sheet(isPresented: $showHosSheet) {
            HosDutyStatus(register: .afternoon)
                .environment(\.palette, palette)
                // Presented as a SHEET here — the 019 top-bar chevron must
                // resolve to the sheet's own `dismiss()`, not the Home
                // lifecycle's `\.driverNavBack` (→ `trip.stepBack()`).
                // Null that env on the sheet content so the chevron's
                // `navBack?()` is a no-op and only `dismiss()` fires; the
                // sheet closes cleanly with no hidden trip-phase rewind.
                .environment(\.driverNavBack, nil)
                .eusoSheetX()
        }
        // EusoWallet — full DriverWalletPane surface with settlements,
        // payouts, and linked-account CTAs.
        .sheet(isPresented: $showWalletSheet) {
            DriverWalletPane()
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        // Home suggested-loads carousel — tapping a card surfaces the
        // same LoadDetailSheet the Eusoboards tab presents so the detail
        // UI stays consistent across entry points. Wired per user
        // direction (2026-04-21):
        //
        //   > when you press it it takes you to the load details
        //
        // LEGACY FALLBACK ONLY since 2026-06-09 (audit M25): carousel
        // taps push in-stack via `\.rolePushDetail`; this presenter
        // fires only when no detail layer is mounted.
        .sheet(item: $selectedSuggestedLoad) { load in
            LoadDetailSheet(load: load)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
        // Notifications inbox surfaced from the home NotificationsWidget
        // tile (and any other tile that posts the same name in future).
        // Wraps the body-only MeNotificationsView with a header + scroll
        // chrome so it stands alone — the MeDetailContainer normally
        // owns chrome for this view inside the Me sub-route.
        .sheet(isPresented: $showNotificationsSheet) {
            DriverHomeNotificationsSheet()
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    // MARK: Assigned-load detail (push-nav, audit M25)

    /// Shared detail body for the active/assigned load. Reuses the
    /// canonical `LoadDetailSheet` the Eusoboards surface renders so
    /// drivers get the same route map, rate breakdown, and broker card
    /// regardless of which surface opened it. Rendered either in-stack
    /// (pushed via `RoleDetailLayer`) or inside the legacy fallback
    /// sheet above. `hostedInPush` threads through to `LoadDetailSheet`
    /// so the push-hosted variant hides its sheet-only close X and exits
    /// via `.eusoRoleNavBack` instead of a dead `dismiss()`.
    @ViewBuilder
    private func assignedLoadDetailContent(hostedInPush: Bool) -> some View {
        if let load = vm.activeLoad {
            LoadDetailSheet(
                load: AvailableLoad.from(
                    load,
                    originCity: vm.originCity,
                    destCity: vm.destCity
                ),
                hostedInPush: hostedInPush
            )
            .environment(\.palette, palette)
        } else {
            // Summary-only fallback — builds a thinner AvailableLoad
            // from the LoadSummary projection so the detail sheet
            // still has enough to render while getById is in flight.
            LoadDetailSheet(
                load: AvailableLoad(
                    id: vm.loadIDDisplay,
                    origin: vm.originCity,
                    destination: vm.destCity,
                    miles: 0,
                    equipment: "-",
                    rate: 0,
                    rpm: 0,
                    pickupWindow: vm.pickupStatusPill,
                    broker: "Dispatch",
                    hazmat: false,
                    weight: "-",
                    hotScore: 0,
                    originLat: 39.8283, originLng: -98.5795,
                    destLat: 39.8283, destLng: -98.5795,
                    // Summary-only fallback — the VM doesn't surface a
                    // mode here; default truck so mode-aware surfaces
                    // read correctly until getById hydrates the row.
                    transportMode: "truck",
                    equipmentRaw: nil
                ),
                hostedInPush: hostedInPush
            )
            .environment(\.palette, palette)
        }
    }

    /// Push-nav entry point for the "Review load brief" CTA. In-stack
    /// push when the Driver surface layer is mounted; legacy slide-up
    /// sheet otherwise.
    private func openAssignedLoadDetail() {
        if let push = pushDetail {
            push("Load brief") { AnyView(assignedLoadDetailContent(hostedInPush: true)) }
        } else {
            showAssignedLoadDetail = true
        }
    }

    // MARK: TopBar

    // Figma 212:444 / SVG 010 — branded eyebrow (EusoTrip mark + DRIVER · DASHBOARD
    // gradient, live status · CITY tertiary on the right), then a two-line
    // display greeting left, uppercase right-column label, chat round button
    // with magenta iridescent badge dot. The eyebrow is the SVG's defining
    // header motif (sparkle glyph used exactly once per surface, §4.3 budget).
    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // Bespoke eyebrow row — gradient role chip + tertiary
            // live status · location, matching the Dark-SVG header and
            // the Shipper-200 idiom so the role homes read as one family.
            HStack {
                EusoTripEyebrow(verbatim: "DRIVER · DASHBOARD")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("\(driverHeaderSignal.uppercased()) · \(vm.locationCity.uppercased())")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            headerRow
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
        // Founder mandate 2026-05-05: replace the bottom-sheet pull-up
        // with a real full-screen messaging page (mirrors the web
        // platform). `MessagesScreen` owns the inbox + push-to-
        // conversation + new-message compose + back chevron.
        .fullScreenCover(isPresented: $showMessages) {
            MessagesScreen()
                .environment(\.palette, palette)
        }
    }

    // Greeting + right-rail location/time + chat glyph. Split out of
    // `topBar` so the new bespoke eyebrow can sit above it without
    // exploding the type-check budget on one giant view literal.
    private var headerRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(greetingFirstName.isEmpty ? "Welcome back" : "Hey, \(greetingFirstName)")
                .font(.system(size: 40, weight: .heavy))
                // Brand gradient on the name reads as EusoTrip-native in
                // both Night and Afternoon. In light mode the prior
                // palette.textPrimary (near-black) flattened the hero line;
                // gradient restores the identity without a color flip.
                .foregroundStyle(LinearGradient.diagonal)
                .lineSpacing(-4)
                .lineLimit(2)
                // Without minimumScaleFactor a long first name (e.g.
                // "Christopherson") forced a 3-line wrap inside the
                // 180pt frame and spilled over the IridescentHairline.
                // With it the text shrinks gracefully so "Hey, Long"
                // and "Welcome back" both fit on two lines without
                // overlapping the right-rail location/time block.
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 180, alignment: .leading)

            Spacer(minLength: 0)

            // Right-rail location — a small gradient pin glyph + city.
            // build-752 feedback B: the time-of-day greeting used to live
            // here too, but it ALSO appears in the eyebrow row above
            // ("GOOD AFTERNOON · CITY"), so it read twice on the header.
            // The greeting now shows once (the eyebrow); the right rail
            // owns the location line only.
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(vm.locationCity)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: 140, alignment: .trailing)
            .padding(.top, Space.s3)

            // Chat glyph + live unread badge. `UnreadMessageStore` is the
            // single source of truth for the badge; it seeds from the
            // `messages.getUnreadCount` tRPC call on app start and
            // increments on `message:new` WebSocket fan-outs.
            MessagesBadgeButton(showMessages: $showMessages, palette: palette)
                .padding(.top, 2)
        }
    }

    private var timeOfDayGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    private var driverHeaderSignal: String {
        switch vm.weatherAvailability {
        case .live: return "Weather live"
        case .needsLocation: return "Location needed"
        case .pending: return "Syncing"
        case .unavailable: return "Weather unavailable"
        }
    }

    // MARK: Loading / empty / error states

    /// The full current-work surface is one movable widget. Its pre-trip
    /// status and load/browse actions therefore disappear with the widget
    /// instead of lingering as fixed duplicates below the grid.
    @ViewBuilder
    private var currentWorkWidget: some View {
        switch vm.phase {
        case .idle, .loading:
            loadingState
        case .loaded:
            VStack(alignment: .leading, spacing: Space.s3) {
                if vm.activeLoadSummary != nil || vm.activeLoad != nil {
                    PreTripDVIRStatusPill()
                    activeLoadCard
                } else {
                    noActiveLoadCard
                }
            }
        case .error:
            EmptyView()
        }
    }

    /// Keeps the catalog HOS tile's original drill-down contract after the
    /// fixed meter strip is removed from Home.
    private var hosHomeWidget: some View {
        Button {
            showHosSheet = true
        } label: {
            HosTrackerWidget()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the HOS duty status port")
    }

    /// Driver Home loading state. Previously leaked backend plumbing
    /// ("Contacting EusoTrip tRPC · loads.search · hos.getStatus") into
    /// production. The rebuilt state shows a dense ambient particle field
    /// inside the active-load card footprint — no diagnostic text, just
    /// brand-identity motion. Matches the user direction (2026-04-20):
    ///
    ///   > when screens are loading it shows this. is there a way to
    ///   > hide that from being seen. maybe make is particles floating
    ///   > in the box like thousands of them …
    private var loadingState: some View {
        ActiveCard {
            LoadingParticleField(count: 160, height: 180)
                .frame(maxWidth: .infinity)
        }
    }

    /// Subtle strip shown when the live backend is unreachable. Server-backed
    /// widgets remain empty; independently sourced WeatherKit data may remain
    /// available.
    private var offlineBanner: some View {
        HStack(spacing: Space.s2) {
            Circle()
                .fill(Brand.warning)
                .frame(width: 6, height: 6)
            Text("Offline · server data unavailable")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Button {
                Task { await vm.load() }
            } label: {
                Text("Retry")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    /// Renders a neutral gradient CTA in place of the WeatherCard when
    /// the driver has denied (or restricted) CoreLocation access. Tapping
    /// the card opens iOS Settings for the app so the driver can toggle
    /// location on — at which point the dashboard's next `.refreshable`
    /// pass will populate `vm.weather` with live WeatherKit data.
    ///
    /// 75th firing (2026-04-24, eusotrip-killers hygiene + fallback C):
    /// introduced so we can honor the "no fake data" doctrine while
    /// still communicating state to the driver. Replaces the old
    /// fabricated `"Enable location for live weather"` WeatherSnapshot
    /// placeholder that rendered a fake 72°/8 mph/10 mi snapshot.
    private var enableLocationCard: some View {
        Button {
            // Three states funnel through this CTA:
            //   • .notDetermined → fire the iOS "Allow location?"
            //     prompt (no Settings detour). After the user taps
            //     Allow, the next `.refreshable` pass populates
            //     `vm.weather` with live data.
            //   • .denied / .restricted → open Settings since iOS
            //     won't re-prompt; the founder needs the kill-switch
            //     in Settings to flip back on.
            // Founder report 2026-05-05 — "the app doesn't ask for
            // my location" — caused by the prior unconditional
            // Settings-deep-link path firing even when the system
            // had never asked.
            let status = WeatherService.shared.authorizationStatus
            if status == .notDetermined {
                WeatherService.shared.requestPermissionIfNeeded()
                Task {
                    // Re-poll the dashboard once the user responds so
                    // the card flips from the CTA into the live
                    // WeatherCard automatically.
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await vm.load()
                }
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 48, height: 48)
                    Image(systemName: "location.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable location for live weather")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Grant location access to see local conditions, visibility and route weather alerts.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            // Bespoke EusoCard surface — iridescent outline + glow so the
            // enable-location CTA reads as a first-class card, not a flat
            // bordered box, matching the SVG card language.
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
    }

    /// Shown when the driver has no active assignment. Replaces the
    /// previous "No active load assigned" dead-end card with a horizontal
    /// carousel of suggested freight — tapping a card opens
    /// `LoadDetailSheet`; the "Browse available loads" button switches
    /// to the Eusoboards tab for the full board. Driver direction
    /// (2026-04-21):
    ///
    ///   > that module should be a carousel of available loads and when
    ///   > you press it it takes you to the load details when you arent
    ///   > in an active load. … the carousel of course should have
    ///   > scroll left to right capability.
    private var noActiveLoadCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // D-1 HERO — "Post your truck → offers come to YOU". The
            // founder's #1 loved feature, surfaced FIRST when the driver
            // is between loads. Push-nav (no slide-up) to the bespoke
            // 113_DriverTruckPosted surface.
            postTruckHeroCTA

            HStack {
                Text("AVAILABLE NEAR YOU")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("Live · \(suggestedLoads.count) loads")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            // Horizontal scroller — snap-paged so each card settles
            // center-of-screen. `.scrollTargetBehavior(.viewAligned)`
            // gives the natural deck feel the driver asked for. When
            // the live store returns zero loads we fall through to the
            // branded EusoEmptyState instead of rendering a mock card.
            if suggestedLoads.isEmpty {
                // Ambient empty state — no truck icon, no "Live · 0 loads"
                // drama. A single muted line that reads like a status,
                // not a card-sized void. The driver's intent from here
                // is to tap "Browse available loads" below; this row
                // just acknowledges the board is quiet right now.
                HStack(spacing: Space.s2) {
                    Circle()
                        .fill(palette.textTertiary.opacity(0.5))
                        .frame(width: 5, height: 5)
                    Text("Quiet on your lane. We'll let you know the moment tenders land.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.vertical, Space.s2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Space.s3) {
                        ForEach(suggestedLoads) { load in
                            Button {
                                // Push-nav (audit M25): in-stack detail
                                // when the layer is mounted; legacy
                                // sheet fallback otherwise.
                                if let push = pushDetail {
                                    push("Load details") {
                                        AnyView(
                                            LoadDetailSheet(load: load,
                                                            hostedInPush: true)
                                                .environment(\.palette, palette)
                                        )
                                    }
                                } else {
                                    selectedSuggestedLoad = load
                                }
                            } label: {
                                SuggestedLoadCard(load: load)
                                    .frame(width: suggestedCardWidth)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Available load \(load.id), \(load.origin) to \(load.destination)")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 2)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }

            Button {
                // Switch the BottomNav to the Trips tab where the full
                // Eusoboards board lives. DriverHome doesn't own the
                // tab state — DriverHomeScreen does — so we fan out a
                // NotificationCenter event it listens for.
                NotificationCenter.default.post(
                    name: .eusoSwitchToTripsTab,
                    object: nil
                )
            } label: {
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Browse available loads")
                        .font(EType.bodyStrong)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Eusoboards load board")
        }
    }

    // MARK: D-1 Post-truck hero CTA (founder's #1 loved feature)

    /// Eye-catching brand-gradient hero that sells the inbound truck-posting
    /// value prop and pushes the bespoke 113 surface. Drawn radar glyph
    /// (no SF Symbol on the gradient slab), the headline, and a confident
    /// "Post your truck" affordance. Tapping anywhere on the card navigates.
    private var postTruckHeroCTA: some View {
        Button {
            openTruckPosting()
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(LinearGradient.diagonal)
                // Ambient "offers travelling toward you" arcs — drawn, faint.
                PostTruckHeroArcs()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1.4)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))

                HStack(spacing: Space.s4) {
                    PostTruckRadarGlyph()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("POST YOUR TRUCK")
                            .font(EType.micro).tracking(1.2)
                            .foregroundStyle(Color.white.opacity(0.9))
                        Text("Offers come to YOU")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(.white)
                        Text("One tap to book · brokers see you live")
                            .font(EType.caption)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .padding(Space.s4)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .shadow(color: Brand.magenta.opacity(0.26), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post your truck. Offers come to you. One tap to book.")
        .accessibilityHint("Opens the inbound truck-posting surface")
    }

    /// Push-nav entry to the bespoke 113 truck-posting surface. In-stack
    /// push when the Driver surface layer is mounted; otherwise a
    /// notification fallback so it still routes from an isolated host.
    private func openTruckPosting() {
        if let push = pushDetail {
            push("Post your truck") {
                AnyView(DriverTruckPosted().environment(\.palette, palette))
            }
        } else {
            NotificationCenter.default.post(
                name: Notification.Name("eusoOpenTruckPostingRequested"),
                object: nil
            )
        }
    }

    /// Target width for each card in the available-loads carousel.
    /// Uses the shell width minus the Home padding so one card sits flush
    /// with the screen and the next card peeks in by ~20% — the classic
    /// "peek-ahead carousel" rhythm from the Figma.
    private var suggestedCardWidth: CGFloat {
        // DriverHome is inside a TileStack padded by Space.s5 (20) on
        // each side. Target: full card = contentWidth - 48 (leaves a
        // 48pt peek for card[n+1] so the driver gets the swipe affordance).
        max(260, Device.width - (Space.s5 * 2) - 48)
    }

    private func errorState(_ message: String) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Brand.warning)
                    Text("Connection unavailable")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Button {
                    Task { await vm.load() }
                } label: {
                    Text("Retry")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .padding(.top, Space.s3)
            }
        }
    }

    // MARK: Active load — live

    private var activeLoadCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                // head row
                HStack {
                    HStack(spacing: Space.s2) {
                        StatusPill(text: vm.pickupStatusPill, kind: .info)
                        if vm.cargoWeightPill != "-" {
                            StatusPill(text: vm.cargoWeightPill, kind: .neutral)
                        }
                        // 2026-05-17 — Driver Home active-load mode
                        // badge. Hidden for the default truck-single-
                        // vehicle case so the home screen stays clean.
                        // The driver is the role most likely to be
                        // *wrong* about mode (a rail engineer assigned
                        // a vessel charter is a disaster), so a single
                        // glance on Home surfaces the truth.
                        LoadModeBadge(modeRaw: vm.activeLoadSummary?.transportMode,
                                      multiVehicleCount: vm.activeLoadSummary?.multiVehicleCount,
                                      compact: true)
                    }
                    Spacer()
                    Text(vm.loadIDDisplay)
                        .font(.system(size: 12, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                }

                // Figma 212:444 — amount on its own line (big gradient),
                // caption (linehaul · $/mi · total miles) on a line below.
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.amountDisplay)
                        .font(.system(size: 52, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(vm.rpmDisplay)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, Space.s4)

                // route row
                HStack(alignment: .top, spacing: Space.s3) {
                    routeNode(timeLabel: vm.originTimeLabel,
                              city: vm.originCity,
                              addr: vm.originAddr,
                              trail: "")
                    gradientArrow
                    routeNode(timeLabel: vm.destTimeLabel,
                              city: vm.destCity,
                              addr: vm.destAddr,
                              trail: "")
                }
                .padding(.top, Space.s4)

                // PNG canon (`01 Driver/{Light,Dark}/010 Driver Home.png`):
                // primary "Continue pre-trip" + outlined "Review load brief".
                // "Continue" honors the in-progress DVIR state surfaced by
                // PreTripDVIRStatusPill above; "Review load brief" routes to
                // the rich LoadDetailSheet (route map + rate breakdown +
                // broker card + permits) rather than a generic metadata pane.
                // PNG canon shows the two CTAs at roughly equal width
                // (50/50). "Review load brief" is wider than the legacy
                // "Details" copy, so the outlined CTA expands with
                // `maxWidth: .infinity` instead of the prior 110pt fixed
                // frame to keep the label on a single line at all device
                // widths.
                HStack(spacing: Space.s2) {
                    LifecycleCTAButton(title: "Continue pre-trip")
                        .frame(maxWidth: .infinity)
                    Button("Review load brief") { openAssignedLoadDetail() }
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(palette.bgCardSoft)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .padding(.top, Space.s5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active load \(vm.loadIDDisplay), \(vm.amountDisplay) \(vm.rpmDisplay)")
    }

    private func routeNode(timeLabel: String, city: String, addr: String, trail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeLabel).font(EType.caption).foregroundStyle(palette.textSecondary)
            Text(city).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(2)
            Text(addr).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            if !trail.isEmpty {
                Text(trail).font(EType.caption).foregroundStyle(palette.textPrimary).monospacedDigit()
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gradientArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(LinearGradient.diagonal)
            .frame(width: 24)
    }

    // MARK: Recent — three activity rows (Figma 212:444)
    //
    // Each row is a live Button that deep-links into the right surface:
    //   · POD filed / settlement preview  → EusoWallet (settlement detail)
    //   · Detention claim approved        → EusoWallet (accessorials)
    //   · Fuel transaction                → EusoWallet (fuel log)
    //
    // Data is sourced from vm.recentActivity (settlements.recentByDriver
    // + fuel.recentByDriver tRPC endpoints). Falls back to on-device demo
    // rows if those endpoints haven't populated yet so the UI keeps its
    // shape during cold-start — the underlying action is always live.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Recent".uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // "See all" routes into the full Wallet sheet (settlements,
                // detentions, fuel — same surface as the Wallet tile above).
                Button("See all") { showWalletSheet = true }
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .underline()
            }

            VStack(spacing: 0) {
                if vm.recentActivity.isEmpty {
                    // Empty state — shown when the driver has no active
                    // load, no duty events, no unread messages, and no
                    // wallet balance fetched yet. Keeps the card's shape
                    // without faking placeholder rows.
                    HStack(spacing: Space.s3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(palette.bgCardSoft)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No recent activity yet")
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            Text("Assignments, duty changes and payouts will show up here.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(vm.recentActivity.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            // Row routing by kind. HOS opens the duty-status
                            // port, messages open the inbox sheet, everything
                            // else (load lifecycle, POD, settlements) opens
                            // the EusoWallet pane — the canonical surface
                            // for settlements, accessorial claims, and fuel.
                            switch item.kind {
                            case .hos:
                                showHosSheet = true
                            case .message:
                                showMessages = true
                            case .load, .document, .payment:
                                showWalletSheet = true
                            }
                        } label: {
                            activityRow(item: item)
                        }
                        .buttonStyle(ActivityRowButtonStyle())
                        .accessibilityLabel(item.title)
                        .accessibilityHint(accessibilityHint(for: item.kind))

                        if idx < vm.recentActivity.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 68)
                        }
                    }
                }
            }
            .eusoCard(radius: Radius.lg)
        }
    }

    /// VoiceOver hint for a recent-activity row. Matches the kind-based
    /// routing above so the announcement actually matches what the tap
    /// will open.
    private func accessibilityHint(for kind: RecentActivityKind) -> String {
        switch kind {
        case .hos:      return "Opens HOS duty status"
        case .message:  return "Opens your inbox"
        case .load, .document, .payment:
            return "Opens in EusoWallet"
        }
    }

    private func activityRow(item: RecentActivityItem) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(item.glyphTint)
                Image(systemName: item.glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.glyphColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.trail)
                    .font(EType.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(item.trailColor)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
    }

    // Reorderable secondary-widget zone moved to the shared
    // HomeWidgetGrid component (defined at file scope above).
    // canonicalOrder + render closure are declared at the top of
    // this struct; nothing else lives here.
}

// MARK: - MessagesWidget (catalog widget id: "messages" · UNIVERSAL)
//
// Universal across all 24 roles. Reads the canonical
// UnreadMessageStore.shared total. Tap dispatches the same
// eusoLogoutRequested-pattern notification every role's topbar
// chat glyph fires, so the universal MessagesScreen surfaces from
// the same path regardless of role context.

struct MessagesWidget: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var unread = UnreadMessageStore.shared

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("eusoOpenMessagesRequested"),
                object: nil
            )
        } label: {
            HStack(spacing: Space.s3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .frame(width: 44, height: 44)
                        .background(palette.bgCardSoft, in: Circle())
                    if unread.total > 0 {
                        Text(unread.total > 99 ? "99+" : "\(unread.total)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Brand.danger, in: Capsule())
                            .offset(x: 6, y: -4)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("MESSAGES")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(unread.total == 0 ? "Inbox clean" : "\(unread.total) unread thread\(unread.total == 1 ? "" : "s")")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Tap to open inbox")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Bespoke EusoCard surface — iridescent outline + glow,
            // replacing the flat bgCard + faint border so the tile reads
            // in the SVG card language.
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DriverHomeNotificationsSheet (wraps MeNotificationsView)
//
// MeNotificationsView is body-only (the MeDetailContainer normally
// supplies the title bar + xmark). This wrapper adds a header strip
// + ScrollView so the same surface stands on its own when presented
// directly from Home.

struct DriverHomeNotificationsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("NOTIFICATIONS")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                        .padding(8)
                        .background(palette.bgCard, in: Circle())
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    MeNotificationsView()
                    Color.clear.frame(height: 32)
                }
                .padding(.horizontal, 14)
                .padding(.top, Space.s3)
            }
        }
        .background(palette.bgPrimary.ignoresSafeArea())
    }
}

// MARK: - NotificationsWidget (catalog widget id: "notifications")
//
// Universal tile — top 3 platform alerts via `notifications.list(limit: 5)`
// with an unread-count badge. Tap posts `eusoOpenNotificationsRequested`
// so each role's shell can route to its own notifications screen.

struct NotificationsWidget: View {
    @Environment(\.palette) private var palette

    private struct AlertItem: Decodable, Identifiable, Hashable {
        let id: String
        let title: String
        let message: String?
        let timeAgo: String?
        let isRead: Bool?
    }
    private struct Page: Decodable {
        let notifications: [AlertItem]
        let total: Int?
    }
    private struct In: Encodable { let limit: Int; let archived: Bool }

    @State private var items: [AlertItem] = []
    @State private var totalUnread: Int = 0
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("eusoOpenNotificationsRequested"),
                object: nil
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("NOTIFICATIONS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer(minLength: 0)
                    if totalUnread > 0 {
                        Text(totalUnread > 99 ? "99+ NEW" : "\(totalUnread) NEW")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Brand.danger, in: Capsule())
                    } else if !loading && loadError == nil {
                        Text("ALL READ")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if loading {
                    Text("Loading alerts…")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else if let err = loadError {
                    Text(err)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .lineLimit(2)
                } else if items.isEmpty {
                    Text("Inbox clean. No platform alerts.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items.prefix(3)) { n in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill((n.isRead ?? true) ? palette.borderFaint : Brand.danger)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.title)
                                        .font(EType.bodyStrong)
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1)
                                    if let m = n.message, !m.isEmpty {
                                        Text(m)
                                            .font(EType.caption)
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if let t = n.timeAgo, !t.isEmpty {
                                    Text(t.uppercased())
                                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text("OPEN INBOX")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Bespoke EusoCard surface — iridescent outline + glow,
            // replacing the flat bgCard + faint border so the tile reads
            // in the SVG card language.
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
        .eusoRefreshTask { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let page: Page = try await EusoTripAPI.shared.query(
                "notifications.list",
                input: In(limit: 5, archived: false)
            )
            await MainActor.run {
                self.items = page.notifications
                self.totalUnread = page.notifications.filter { !($0.isRead ?? true) }.count
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
                self.loading = false
            }
        }
    }
}

// MARK: - WeatherTileWidget (catalog widget id: "weather" — universal)
//
// Span-aware wrapper around the canonical WeatherCard so the universal
// cross-platform "weather" tile renders the real freight weather card:
// `.half` → the compact one-row glance, `.full` → the full card with
// the lane strip. Reads the same live snapshot the hero renders.

struct WeatherTileWidget: View {
    @Environment(\.palette) private var palette
    @Environment(\.homeWidgetSpan) private var span
    @Environment(\.scenePhase) private var scenePhase
    let snapshot: WeatherSnapshot?
    var lane: LaneWeather? = nil

    // Mirrors the live CoreLocation state so the nil card can offer the
    // RIGHT CTA (system prompt vs. Settings) and re-render when the user
    // responds. Seeded from the service so a returning view is correct
    // before the first scenePhase tick. (build-752 feedback A)
    @State private var authStatus: CLAuthorizationStatus = WeatherService.shared.authorizationStatus

    var body: some View {
        Group {
            if let s = snapshot {
                WeatherCard(
                    snapshot: s,
                    lane: span == .half ? nil : lane,
                    style: span == .half ? .compact : .full
                )
            } else {
                // No live snapshot — an INTERACTIVE enable-location card,
                // not dead text. Tapping fires the iOS prompt (or opens
                // Settings if denied) so HERE + WeatherKit can light up.
                WeatherWidgetEnableLocationCard(status: authStatus, compact: span == .half) {
                    authStatus = WeatherService.shared.authorizationStatus
                }
            }
        }
        // Re-read the auth state on foreground so a grant made in the
        // system prompt (or a toggle in Settings) flips the card's CTA
        // and lets the parent VM's next load() repopulate the snapshot.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { authStatus = WeatherService.shared.authorizationStatus }
        }
    }
}

// MARK: - WeatherAlertsWidget (catalog widget id: "weather_alerts")
//
// Route-relevant weather tile — level-100 rebuild (2026-06-11):
//   • Severe-alert line with real NWS CAP severity color.
//   • Active-load lane row (pickup → delivery live conditions) +
//     freight flags (high-profile wind, chain-law, low-vis, reefer).
//   • Wind (+gust) / visibility / humidity readouts — live or em-dash.
//   • Span-aware: `.half` stays a tight glance, `.full` adds a
//     6-hour mini band.
// Reads from the same WeatherSnapshot + LaneWeather the hero
// WeatherCard renders — composable, no second fetch.

struct WeatherAlertsWidget: View {
    @Environment(\.palette) private var palette
    @Environment(\.homeWidgetSpan) private var span
    @Environment(\.scenePhase) private var scenePhase
    let snapshot: WeatherSnapshot?
    var lane: LaneWeather? = nil

    // Live CoreLocation state so the nil branch's enable card offers the
    // right CTA and re-renders on grant. (build-752 feedback A)
    @State private var authStatus: CLAuthorizationStatus = WeatherService.shared.authorizationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: snapshot?.symbol ?? "cloud.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("WEATHER · ROUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let s = snapshot { Text(s.city).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary) }
            }
            if let s = snapshot {
                // Headline — active CAP bulletin wins (severity-colored),
                // then the forward-looking nextAlert nudge, then current.
                if let top = s.topAlert ?? lane?.topAlert {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(top.severity.color)
                        Text(top.event)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Text(top.severity.label)
                            .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(top.severity.color))
                    }
                } else if let alert = s.nextAlert, !alert.isEmpty {
                    Text(alert)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                } else {
                    Text("\(s.tempF)°F · \(s.condition)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }

                HStack(spacing: 12) {
                    Label(s.windDisplay, systemImage: "wind")
                        .foregroundStyle(s.windHazard ? Brand.warning : palette.textSecondary)
                    Label(s.visibilityDisplay, systemImage: "eye")
                        .foregroundStyle(s.visibilityHazard ? Brand.warning : palette.textSecondary)
                    Label(s.humidityDisplay, systemImage: "humidity")
                        .foregroundStyle(palette.textSecondary)
                }
                .font(.system(size: 11, weight: .semibold))

                // Active-load lane — live pickup → delivery readings.
                if let lane, !lane.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(lane.points.enumerated()), id: \.offset) { idx, point in
                            if idx > 0 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: point.snapshot.symbol)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 10))
                                Text("\(point.city) \(point.snapshot.tempDisplay)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(palette.textPrimary)
                        }
                        Spacer(minLength: 0)
                    }
                    if !lane.flags.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(lane.flags) { flag in
                                HStack(spacing: 4) {
                                    Image(systemName: flag.icon)
                                        .font(.system(size: 8, weight: .bold))
                                    Text(flag.label)
                                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(flag.accent.color)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(flag.accent.color.opacity(0.14)))
                            }
                        }
                    }
                }

                // Full-width span earns the 6-hour mini band.
                if span == .full, !s.hourly.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(s.hourly.prefix(6)) { hour in
                            VStack(spacing: 2) {
                                Text(hour.hourLabel)
                                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                                    .foregroundStyle(palette.textTertiary)
                                Image(systemName: hour.symbol)
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.textSecondary)
                                Text("\(hour.tempF)°")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 2)
                }
            } else {
                // No live snapshot — an INTERACTIVE enable row under the
                // existing "WEATHER · ROUTE" eyebrow (the tile keeps its
                // own card chrome). Tapping fires the iOS prompt (or opens
                // Settings if denied) so HERE + WeatherKit can light up.
                WeatherWidgetEnableRow(status: authStatus) {
                    authStatus = WeatherService.shared.authorizationStatus
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
        // Re-read the auth state on foreground so a grant flips the CTA
        // and the parent VM's next load() repopulates the snapshot.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { authStatus = WeatherService.shared.authorizationStatus }
        }
    }
}

// MARK: - Weather widget enable-location CTA (bespoke, build-752 feedback A)
//
// The interactive enable-location surfaces for the catalog weather tiles.
// Reuses the working hero `enableLocationCard` behavior (notDetermined →
// fire the iOS prompt; denied/restricted → open Settings) but rendered to
// each tile's idiom: a full card for `WeatherTileWidget`, a compact row
// under the existing eyebrow for `WeatherAlertsWidget`. Glyphs come from
// the WeatherIcons utility corpus (no SF Symbols), matching the weather
// surfaces. After the tap settles, posts `.esangRefreshSurface` so the
// parent DriverHome re-runs `vm.load()` and repopulates `vm.weather` —
// flipping the card from CTA → live data with no VM threading.

/// Funnels a tap into the right CoreLocation action, then nudges the host
/// surface to refetch. `onResolved` lets the caller re-read the live auth
/// status so the CTA copy/state updates immediately on the tap.
///
/// @MainActor: `WeatherService.shared` and its `authorizationStatus` /
/// `requestPermissionIfNeeded()` are MainActor-isolated. The only callers
/// are the two enable-location cards' `Button` actions, which already run
/// on the main actor, so isolating this helper is free and correct.
@MainActor
/// `openURL` is passed in because this is a free function, not a View, so it has
/// no `@Environment` of its own. It used to reach for the raw UIKit opener
/// instead — the call that was driven to zero under `Views/` on purpose, so its
/// reappearance is by definition a regression. It had reappeared here.
private func weatherWidgetHandleEnableTap(openURL: OpenURLAction, onResolved: @escaping () -> Void) {
    let status = WeatherService.shared.authorizationStatus
    if status == .notDetermined {
        WeatherService.shared.requestPermissionIfNeeded()
        Task {
            // Give CoreLocation a beat to deliver the grant + first fix,
            // then ask DriverHome to re-load so `vm.weather` repopulates.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                onResolved()
                NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
            }
        }
    } else if let url = URL(string: UIApplication.openSettingsURLString) {
        openURL(url)
    }
}

/// Full enable-location card for the universal "weather" tile. Span-aware:
/// compact (half) drops the body copy to one tight line.
private struct WeatherWidgetEnableLocationCard: View {
    let status: CLAuthorizationStatus
    var compact: Bool = false
    var onResolved: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    private var denied: Bool { status == .denied || status == .restricted }

    var body: some View {
        Button {
            weatherWidgetHandleEnableTap(openURL: openURL, onResolved: onResolved)
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: compact ? 38 : 48, height: compact ? 38 : 48)
                    WeatherIcons.utility(.pin, size: compact ? 17 : 22, tint: .white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(denied ? "Turn location on in Settings" : "Enable location for live weather")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    if !compact {
                        Text(denied
                             ? "Location is off for EusoTrip. Tap to open Settings and turn it on for local conditions and route weather."
                             : "Grant location access to see local conditions, visibility and route weather alerts.")
                            .font(EType.micro)
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                WeatherIcons.utility(.chev, size: 13, tint: palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(denied ? "Turn location on in Settings" : "Enable location for live weather")
        .accessibilityHint(denied
                           ? "Opens Settings so you can turn location on for the weather tile."
                           : "Grants location access so the weather tile can show local conditions.")
    }
}

/// Compact enable-location row for the "weather_alerts" tile — rendered
/// under that tile's own "WEATHER · ROUTE" eyebrow + card chrome.
private struct WeatherWidgetEnableRow: View {
    let status: CLAuthorizationStatus
    var onResolved: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL

    private var denied: Bool { status == .denied || status == .restricted }

    var body: some View {
        Button {
            weatherWidgetHandleEnableTap(openURL: openURL, onResolved: onResolved)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 30, height: 30)
                    WeatherIcons.utility(.pin, size: 14, tint: .white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(denied ? "Turn location on in Settings" : "Enable location for live route weather")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                    Text(denied ? "Tap to open Settings" : "Tap to allow location")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                WeatherIcons.utility(.chev, size: 11, tint: palette.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(denied ? "Turn location on in Settings" : "Enable location for live route weather")
        .accessibilityHint(denied
                           ? "Opens Settings so you can turn location on for route weather."
                           : "Grants location access so route weather can load.")
    }
}

// MARK: - EarningsSummaryWidget (catalog widget id: "earnings_summary")
//
// Snapshot of wallet available + pending + last payout. Reads the
// live wallet snapshot the home VM already polls (vm.walletAvailable
// + sibling fields). Tap routes to EusoWallet via the existing
// notification path.

struct EarningsSummaryWidget: View {
    @Environment(\.palette) private var palette
    let available: Double?
    let availableDisplay: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("EARNINGS · WALLET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("EUSOWALLET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("AVAILABLE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(availableDisplay)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
            if available == nil {
                Text("Sign in or wait for first sync. EusoWallet shows here once a balance lands.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
    }
}

// MARK: - NextDeliveryWidget (catalog widget id: "next_delivery")
//
// Glanceable next-delivery tile pulled from the same LoadSummary the
// home's hero activeLoadCard renders. Composes a tight 3-line card:
// load number + lane + pickup date so the driver has the destination
// + ETA at the top of the customizable widget zone without the full
// hero card weight.

struct NextDeliveryWidget: View {
    @Environment(\.palette) private var palette
    let summary: LoadSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("NEXT \((TransportMode(rawValue: summary?.transportMode ?? "truck") ?? .truck).deliveryNoun)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let s = summary {
                    Text(s.status.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if let s = summary {
                Text(s.loadNumber)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("\(s.origin)  →  \(s.destination)")
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(s.pickupDate)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    if s.rate > 0 {
                        Text("$\(Int(s.rate).formatted())")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                    }
                }
            } else {
                Text("No load assigned. Accept a tender to populate.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
    }
}

// MARK: - HosTrackerWidget (catalog widget id: "hos_tracker")
//
// First port of a web-catalog widget to an iOS tile-card. Wraps the
// existing HosTile primitive with a card shell + tap-to-open the
// full 019_HosDutyStatus surface. Reads live data from
// HOSClockService.shared (already booted by EusoTripApp).

struct HosTrackerWidget: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var hos = HOSClockService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(hos.status?.hasCurrentObservation() == true ? "HOS · LIVE" : "HOS · UNAVAILABLE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let s = hos.status, s.hasCurrentObservation(), let canDrive = s.canDrive {
                    Text(canDrive ? "CAN DRIVE" : "NOT ELIGIBLE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(canDrive ? Color.green.opacity(0.85) : Brand.danger)
                        .clipShape(Capsule())
                }
            }
            if let s = hos.status, s.hasCurrentObservation() {
                HStack(spacing: Space.s2) {
                    HosTile(value: s.drivingRemainingDisplay, label: "DRIVE")
                    HosTile(value: s.onDutyRemainingDisplay, label: "ON-DUTY")
                    HosTile(value: s.cycleRemainingDisplay, label: "CYCLE")
                }
            } else {
                Text(hos.lastRefreshError ?? "Current HOS evidence is unavailable.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
    }
}

/// Tapped-state styling for activity rows — soft scale + flash so the
/// tap feedback reads without pulling the whole row off the card. Keeps
/// the EusoCard hairline intact underneath.
private struct ActivityRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - HosTile (Figma 212:444)
/// Split-gradient HOS drive-left tile — hours in Brand.blue, minutes in Brand.magenta,
/// with tiny lowercase "h" / "m" unit suffixes baselined under the numerals.
private struct HosTile: View {
    let value: String
    /// Override the eyebrow label. Default keeps the original
    /// `HOS DRIVE LEFT` rendering for legacy callers; the 3-meter strip
    /// passes `DRIVE` / `ON-DUTY` / `CYCLE` to mirror the §395.3 PNG
    /// canon (49 CFR 395.3(a)(3)(i) drive · §395.3(a)(2) on-duty ·
    /// §395.3(b) cycle).
    var label: String = "HOS DRIVE LEFT"
    @Environment(\.palette) var palette

    /// Parse "7h 22m" → (hours, minutes). Falls back gracefully on "-" / bad input.
    private var parts: (hours: String, minutes: String)? {
        let s = value.replacingOccurrences(of: " ", with: "")
        guard let hIdx = s.firstIndex(of: "h") else { return nil }
        let h = String(s[..<hIdx])
        let after = s.index(after: hIdx)
        let rest = String(s[after...]).replacingOccurrences(of: "m", with: "")
        guard !h.isEmpty else { return nil }
        return (h, rest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if let p = parts {
                    // Numeric duotone — both hours and minutes read
                    // through the brand gradient so the whole clock
                    // value reads as a single gradient numeric per the
                    // doctrine ("gradient, not blue"). The blue→magenta
                    // split is already carried by LinearGradient.diagonal
                    // (topLeading → bottomTrailing).
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(p.hours)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("h")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .padding(.trailing, 4)
                        Text(p.minutes)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("m")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    .monospacedDigit()
                } else {
                    Text(value)
                        .font(EType.numeric)
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }
}

// MARK: - MileageTrackerWidget (catalog widget id: "mileage_tracker")
//
// Monthly miles tile. Pulls `totalMiles` from `drivers.getPerformanceMetrics`
// for the month-to-date figure. Also surfaces the active load's distance
// (passed from the home VM) so the driver can see their current-haul
// mileage at a glance alongside the rolling monthly total.

struct MileageTrackerWidget: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// Miles on the current active load — nil when the driver is between loads.
    let currentLoadMiles: Double?

    @State private var monthlyMiles: Double? = nil
    @State private var totalLoads: Int? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private static let miFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private func fmt(_ miles: Double) -> String {
        Self.miFormatter.string(from: NSNumber(value: miles)) ?? String(Int(miles))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "road.lanes")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("MILEAGE · THIS MONTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let loads = totalLoads {
                    Text("\(loads) LOADS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if loading {
                Text("Loading mileage…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(monthlyMiles.map { fmt($0) } ?? "-")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("mi")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                if let loadMi = currentLoadMiles, loadMi > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Current haul: \(fmt(loadMi)) mi")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                } else if monthlyMiles == nil {
                    Text("No mileage data yet for this period.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
        .eusoRefreshTask { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        let userId = session.user?.id ?? ""
        guard !userId.isEmpty else { loading = false; return }
        do {
            let sc = try await EusoTripAPI.shared.drivers.getPerformanceMetrics(
                driverId: userId, period: .month
            )
            monthlyMiles = sc.tracked?.mileage == true ? sc.metrics.totalMiles : nil
            totalLoads = sc.tracked?.loads == true ? sc.metrics.totalLoads : nil
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - WalletActivityWidget (catalog widget id: "wallet_activity")
//
// Driver's latest EusoWallet movements — payouts, bonuses, fees,
// factoring. Real data via `wallet.getTransactions`
// (frontend/server/routers/wallet.ts:371) projected onto WalletTxn.
// Honors `\.homeWidgetSpan`: `.compact` shows the 2 most recent rows,
// `.full` shows up to 5. No fabricated rows — an empty wallet renders
// the honest empty state.

struct WalletActivityWidget: View {
    @Environment(\.palette) private var palette
    @Environment(\.homeWidgetSpan) private var span

    @State private var txns: [WalletTxn] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private var rowCount: Int { span == .compact ? 2 : 5 }

    private static let amtFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 2
        return f
    }()

    private func amountDisplay(_ t: WalletTxn) -> String {
        let f = Self.amtFormatter
        f.currencyCode = t.currency ?? "USD"
        let s = f.string(from: NSNumber(value: abs(t.amount))) ?? String(format: "%.2f", abs(t.amount))
        return (t.amount < 0 ? "−" : "+") + s
    }

    private func icon(for t: WalletTxn) -> String {
        if let hint = t.iconHint, !hint.isEmpty { return hint }
        switch t.kind {
        case "load_payout":    return "shippingbox.fill"
        case "instant_payout": return "bolt.fill"
        case "bonus":          return "star.fill"
        case "fee":            return "minus.circle.fill"
        case "refund":         return "arrow.uturn.backward.circle.fill"
        case "factoring":      return "building.columns.fill"
        case "fuel":           return "fuelpump.fill"
        default:               return "dollarsign.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("WALLET · ACTIVITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("EUSOWALLET")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            if loading {
                Text("Loading activity…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else if txns.isEmpty {
                Text("No wallet activity yet. Completed load payouts and bonuses land here.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(txns.prefix(rowCount))) { t in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: t))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LinearGradient.diagonal)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                if let sub = t.subtitle, !sub.isEmpty {
                                    Text(sub)
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(palette.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            Text(amountDisplay(t))
                                .font(.system(size: 13, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(t.amount < 0 ? palette.textSecondary : Color.green)
                        }
                    }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
        .eusoRefreshTask { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let resp = try await EusoTripAPI.shared.walletExtras.getTransactions(limit: 6)
            txns = resp.items
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - FuelEconomyWidget (catalog widget id: "fuel_economy")
//
// Month-to-date fuel efficiency glance. Real data via
// `drivers.getPerformanceMetrics` (frontend/server/routers/drivers.ts:544)
// whose `fuelEfficiency` is loads.distance / fuelTransactions.gallons —
// a real numerator, zeroed (not fabricated) when there's no fuel data
// in the window. `totalMiles` is the same period's driven miles. Cost /
// mile is derived only when a real fuel-spend figure is available; we
// never invent a fuel price.

struct FuelEconomyWidget: View {
    @Environment(\.palette) private var palette
    @Environment(\.homeWidgetSpan) private var span
    @EnvironmentObject private var session: EusoTripSession

    @State private var mpg: Double? = nil
    @State private var miles: Double? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private static let oneDecimal: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.maximumFractionDigits = 1; f.minimumFractionDigits = 1; return f
    }()
    private static let whole: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.maximumFractionDigits = 0; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "fuelpump.circle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FUEL · THIS MONTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
            }
            if loading {
                Text("Loading fuel economy…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else if let m = mpg, m > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Self.oneDecimal.string(from: NSNumber(value: m)) ?? String(format: "%.1f", m))
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("mpg")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                if span != .compact, let mi = miles, mi > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "road.lanes")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("\(Self.whole.string(from: NSNumber(value: mi)) ?? String(Int(mi))) mi driven")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            } else {
                Text("No fuel data yet this month. Logged fuel transactions populate your MPG here.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
        .eusoRefreshTask { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        let userId = session.user?.id ?? ""
        guard !userId.isEmpty else { loading = false; return }
        do {
            let sc = try await EusoTripAPI.shared.drivers.getPerformanceMetrics(
                driverId: userId, period: .month
            )
            mpg = sc.tracked?.fuel == true ? sc.metrics.fuelEfficiency : nil
            miles = sc.tracked?.mileage == true ? sc.metrics.totalMiles : nil
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - VehicleHealthWidget (catalog widget id: "vehicle_health")
//
// Driver's assigned-truck glance card. Reads `vehicle.getAssigned` for
// unit number, year/make/model, fuel level, odometer, and status.
// Odometer + fuelLevel remain nil until a telematics source reports them.
// A real zero is still an observation and must render as such; only absence
// produces the unavailable disclosure. No fake data.

struct VehicleHealthWidget: View {
    @Environment(\.palette) private var palette

    private typealias Vehicle = VehicleAPI.AssignedVehicle

    @State private var vehicle: Vehicle? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var statusColor: Color {
        switch vehicle?.status.lowercased() {
        case "active":       return .green
        case "maintenance":  return Brand.warning
        case "out_of_service": return Brand.danger
        default:             return palette.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("VEHICLE · HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let v = vehicle, !v.isUnassigned {
                    Text(v.status.uppercased().replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusColor, in: Capsule())
                }
            }
            if loading {
                Text("Loading vehicle…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else if let v = vehicle, !v.isUnassigned {
                Text("\(v.year) \(v.make) \(v.model)")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Unit \(v.unitNumber)  ·  \(v.licensePlate)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                if v.fuelLevel != nil || v.odometer != nil {
                    HStack(spacing: 12) {
                        if let fuelLevel = v.fuelLevel {
                            Label(String(format: "%.0f%% fuel", fuelLevel * 100), systemImage: "fuelpump.fill")
                        }
                        if let odometer = v.odometer {
                            Label("\(odometer.formatted()) mi", systemImage: "gauge.with.dots.needle.33percent")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                } else {
                    Text("Fuel and odometer telemetry are unavailable.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 2)
                }
            } else {
                Text("No vehicle assigned.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
        .eusoRefreshTask { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let v = try await EusoTripAPI.shared.vehicle.getAssigned()
            vehicle = v
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - PerformanceScoreWidget (catalog widget id: "performance_score")
//
// Monthly driver scorecard tile. Reads safetyScore + onTimeDeliveryRate
// + fleet rank from `drivers.getPerformanceMetrics`. Self-fetches on
// appear using the signed-in user's id from the session environment.

struct PerformanceScoreWidget: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    private struct Snapshot {
        let safetyScore: Double?
        let onTimeRate: Double?
        let rank: Int?
        let totalDrivers: Int

        var hasEvidence: Bool { safetyScore != nil || onTimeRate != nil }
    }

    @State private var snap: Snapshot? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("PERFORMANCE · MONTHLY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let s = snap, let rank = s.rank {
                    Text("#\(rank) of \(s.totalDrivers)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if loading {
                Text("Loading score…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else if let s = snap, s.hasEvidence {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(s.safetyScore.map { String(format: "%.0f", $0) } ?? "—")
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("/ 100")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Text(s.safetyScore == nil ? "NOT TRACKED" : "SAFETY SCORE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(spacing: 12) {
                    if let onTimeRate = s.onTimeRate {
                        Label(String(format: "%.0f%%", onTimeRate), systemImage: "checkmark.circle.fill")
                        Text("on-time")
                    } else {
                        Text("On-time delivery is not tracked yet.")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            } else {
                Text("No performance data yet for this period.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
        .eusoRefreshTask { await load() }
    }

    private func load() async {
        loading = true; loadError = nil
        let userId = session.user?.id ?? ""
        guard !userId.isEmpty else { loading = false; return }
        do {
            let sc = try await EusoTripAPI.shared.drivers.getPerformanceMetrics(
                driverId: userId, period: .month
            )
            snap = Snapshot(
                safetyScore: sc.tracked?.safety == true ? sc.metrics.safetyScore : nil,
                onTimeRate: sc.tracked?.onTime == true ? sc.metrics.onTimeDeliveryRate : nil,
                rank: sc.tracked?.rankings == true && sc.rankings.overall > 0
                    ? sc.rankings.overall
                    : nil,
                totalDrivers: sc.rankings.totalDrivers
            )
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - RestAreasWidget (catalog widget id: "rest_areas")
//
// Top-3 truck stops within 40 km of the driver's current position.
// Uses DriverLocationResolver.shared for a cached GPS coordinate, then
// queries HereParkingClient.parkingNearby with category "400-4100-0199"
// (truck stops in the HERE Places taxonomy).

struct RestAreasWidget: View {
    @Environment(\.palette) private var palette

    @State private var stops: [HereBrowseParkingItem] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var locationDenied = false

    private func fmtDist(_ meters: Int) -> String {
        let miles = Double(meters) / 1609.34
        if miles < 0.1 { return "< 0.1 mi" }
        if miles < 10  { return String(format: "%.1f mi", miles) }
        return "\(Int(miles)) mi"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("REST AREAS · NEARBY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("TRUCK STOPS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            if loading {
                Text("Locating rest areas…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if locationDenied {
                Text("Enable location access to see nearby rest areas.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else if stops.isEmpty {
                Text("No truck stops found within 25 mi.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(stops.prefix(3), id: \.id) { stop in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stop.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                if let addr = stop.address?.city, !addr.isEmpty {
                                    Text(addr)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                            Spacer(minLength: 0)
                            if let dist = stop.distance {
                                Text(fmtDist(dist))
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(LinearGradient.diagonal)
                                    .monospacedDigit()
                            }
                        }
                        if stop.id != stops.prefix(3).last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
        .eusoRefreshTask { await load() }
    }

    private func load() async {
        loading = true; loadError = nil; locationDenied = false
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            locationDenied = true; loading = false; return
        }
        do {
            stops = try await HereParkingClient.shared.parkingNearby(
                center: coord, categories: ["400-4100-0199"], limit: 5
            )
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - FuelStationsWidget (catalog widget id: "fuel_stations")
//
// Top-3 diesel stops within 40 km of the driver's current position.
// Uses DriverLocationResolver.shared for a cached GPS coordinate, then
// queries HereFuelPricesClient.nearby. Sorted cheapest-first on diesel
// price; falls back to distance when price data is absent.

struct FuelStationsWidget: View {
    @Environment(\.palette) private var palette

    @State private var stations: [HereFuelStation] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var locationDenied = false

    private func fmtDist(_ meters: Int) -> String {
        let miles = Double(meters) / 1609.34
        if miles < 0.1 { return "< 0.1 mi" }
        if miles < 10  { return String(format: "%.1f mi", miles) }
        return "\(Int(miles)) mi"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FUEL STATIONS · NEARBY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("DIESEL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            if loading {
                Text("Locating fuel stops…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if locationDenied {
                Text("Enable location access to see nearby fuel stops.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else if let err = loadError {
                Text(err)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .lineLimit(2)
            } else if stations.isEmpty {
                Text("No diesel stops found within 25 mi.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(stations.prefix(3), id: \.id) { station in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(station.name ?? "")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                if let brand = station.brand, !brand.isEmpty {
                                    Text(brand)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 1) {
                                if let price = station.cheapestDieselPrice {
                                    Text(String(format: "$%.3f", price.price))
                                        .font(.system(size: 13, weight: .heavy))
                                        .foregroundStyle(LinearGradient.diagonal)
                                        .monospacedDigit()
                                }
                                if let dist = station.distance {
                                    Text(fmtDist(dist))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                        }
                        if station.id != stations.prefix(3).last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
        .eusoRefreshTask { await load() }
    }

    private func load() async {
        loading = true; loadError = nil; locationDenied = false
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            locationDenied = true; loading = false; return
        }
        do {
            let raw = try await HereFuelPricesClient.shared.nearby(
                center: coord, radiusMeters: 40_000, fuelTypes: ["diesel"]
            )
            stations = raw
                .sorted {
                    let p0 = $0.cheapestDieselPrice?.price ?? Double.greatestFiniteMagnitude
                    let p1 = $1.cheapestDieselPrice?.price ?? Double.greatestFiniteMagnitude
                    if p0 != p1 { return p0 < p1 }
                    return ($0.distance ?? Int.max) < ($1.distance ?? Int.max)
                }
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - NearMeLoadIntelWidget (catalog widget id: "near_me_intel")
//
// The driver-facing surface for the ML load intelligence + near-me
// hot-zone market intel the platform already computes server-side but
// never showed the driver. Anchored on the driver's live CoreLocation
// fix, it calls `hotZones.getDriverOpportunities(lat,lng,radius)` — the
// same engine that powers the web driver map's "best loads near you"
// layer — and surfaces, for each near-me hot zone:
//
//   • ML lane scoring   — the H3 AI proximity rank (server sorts by it)
//   • L/T ratio + surge — the REAL load-to-truck pressure & multiplier
//                         for the driver's AREA (task B), not national
//   • est. earnings     — the ML projection (avgRate × distance × 0.85)
//   • avg $/mi          — the zone's live rate
//
// Honesty envelope (rate-vs-market doctrine): every metric the server
// omits renders as an em-dash — NEVER a fabricated rate/ratio/score.
// Bounded load: the shared EusoTripAPI session carries the 22 s request
// ceiling, and every isLoading flag resolves. Location-denied + empty +
// error are all real, distinct states. Flip-card doctrine: the lead
// opportunity FLIPS in place to reveal the ML "why this zone is hot"
// reasons + earnings breakdown rather than pushing a detail screen.

struct NearMeLoadIntelWidget: View {
    @Environment(\.palette) private var palette

    @State private var opportunities: [DriverOpportunity] = []
    @State private var roleContext: DriverOpportunityRoleContext? = nil
    @State private var searchRadius: Int? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var locationDenied = false
    @State private var lastLoadedAt: Date? = nil
    /// Flip state for the lead opportunity card (flip-card doctrine).
    @State private var leadFlipped = false

    /// The server's secondary-metric label for the DRIVER role
    /// ("Est. Earnings"), falling back to a neutral default.
    private var earningsLabel: String {
        roleContext?.secondaryMetric?.uppercased() ?? "EST. EARNINGS"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            header
            if loading && opportunities.isEmpty {
                loadingState
            } else if locationDenied {
                locationDeniedState
            } else if let err = loadError, opportunities.isEmpty {
                errorState(err)
            } else if opportunities.isEmpty {
                emptyState
            } else {
                content
            }
            footerMeta
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow, matching the sibling driver-home tiles.
        .eusoCard(radius: Radius.lg)
        .eusoRefreshTask { await load() }
        .onAppear {
            // Re-fetch on every reappear (not just first mount) so a
            // driver who moved sees fresh near-me intel — same cadence
            // the HotZonesWidget uses for "always fresh when looked at".
            if lastLoadedAt != nil { Task { await load() } }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("NEAR ME · LOAD INTEL")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: 0)
            // Radius badge — the REAL search radius the server scanned.
            if let r = searchRadius {
                Text("\(r) mi")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            // ESANG attribution — this is the ML lane-scoring surface.
            HStack(spacing: 3) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .heavy))
                Text("ESANG")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
            }
            .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        // Lead opportunity — the top AI-proximity-ranked zone, rendered
        // as a flip card (front = the headline lane signal, back = the
        // ML reasons + earnings breakdown).
        if let lead = opportunities.first {
            leadCard(lead)
        }
        // The next near-me zones as a horizontal rail of compact chips.
        if opportunities.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    ForEach(Array(opportunities.dropFirst().prefix(5).enumerated()), id: \.element.zoneId) { pair in
                        oppChip(pair.element, rank: pair.offset + 2)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Lead flip card

    private func leadCard(_ opp: DriverOpportunity) -> some View {
        let demand = HotZoneDemand(demandTier(opp.loadToTruckRatio))
        return ZStack {
            if leadFlipped {
                leadBack(opp)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                leadFront(opp, demand: demand)
            }
        }
        .rotation3DEffect(.degrees(leadFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .animation(.easeInOut(duration: 0.45), value: leadFlipped)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.45)) { leadFlipped.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(opp.zoneName), \(opp.distance) miles. Tap to flip for the load intelligence breakdown.")
    }

    private func leadFront(_ opp: DriverOpportunity, demand: HotZoneDemand) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                // #1 rank dot — the server already sorted by AI proximity.
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 20, height: 20)
                    Image(systemName: "scope")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(opp.zoneName)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("\(opp.distance) mi away")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                Text(demand.label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(demand.color)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(demand.color.opacity(0.16)))
            }
            // Headline signal row — REAL near-me L/T ratio + surge + est.
            // earnings. Em-dash on any absent metric.
            HStack(spacing: Space.s3) {
                signalChip(
                    label: "L/T RATIO",
                    value: String(format: "%.1fx", opp.loadToTruckRatio),
                    tint: Brand.warning
                )
                signalChip(
                    label: "SURGE",
                    value: String(format: "%.2fx", opp.surgeMultiplier),
                    tint: demand.color
                )
                signalChip(
                    label: earningsLabel,
                    value: opp.estimatedEarnings.map { "$\(Int($0).formatted())" } ?? "—",
                    tint: Brand.success
                )
            }
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                Text(String(format: "$%.2f /mi avg", opp.avgRate))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Text("Why it's hot")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient(colors: [demand.color.opacity(0.16), palette.bgCard],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
        )
    }

    private func leadBack(_ opp: DriverOpportunity) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("WHY \(opp.zoneName.uppercased()) IS HOT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            // ML "why this zone is hot" reasons — straight from the server.
            if let reasons = opp.reasons, !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(reasons.prefix(3), id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(LinearGradient.diagonal)
                                .padding(.top, 2)
                            Text(reason)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                // Honest empty — no fabricated rationale.
                Text("No lane drivers published for this zone yet.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Divider().overlay(palette.borderFaint)
            // Earnings breakdown — the ML projection spelled out.
            HStack(spacing: Space.s3) {
                backStat(label: earningsLabel,
                         value: opp.estimatedEarnings.map { "$\(Int($0).formatted())" } ?? "—",
                         tint: AnyShapeStyle(Brand.success))
                backStat(label: "AVG RATE",
                         value: String(format: "$%.2f", opp.avgRate),
                         tint: AnyShapeStyle(LinearGradient.diagonal))
                if !opp.topEquipment.isEmpty {
                    backStat(label: "EQUIP",
                             value: prettyEquip(opp.topEquipment.first ?? "—"),
                             tint: AnyShapeStyle(palette.textPrimary))
                }
            }
            Text("Tap to flip back")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
        )
    }

    private func backStat(label: String, value: String, tint: AnyShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Signal chip (front headline metrics)

    private func signalChip(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(tint.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(tint.opacity(0.40), lineWidth: 1))
    }

    // MARK: Compact opportunity chip (rail)

    private func oppChip(_ opp: DriverOpportunity, rank: Int) -> some View {
        let demand = HotZoneDemand(demandTier(opp.loadToTruckRatio))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ZStack {
                    Circle().fill(demand.color.opacity(0.18)).frame(width: 16, height: 16)
                    Text("\(rank)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(demand.color)
                }
                Text(opp.zoneName)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Text("\(opp.distance) mi")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1fx", opp.loadToTruckRatio))
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("L/T")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(opp.estimatedEarnings.map { "~$\(Int($0).formatted())" } ?? "—")
                .font(.system(size: 11, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Brand.success)
        }
        .padding(Space.s2)
        .frame(width: 124, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(demand.color.opacity(0.45), lineWidth: 1))
    }

    // MARK: States

    private var loadingState: some View {
        HStack(spacing: Space.s2) {
            ProgressView().tint(palette.textSecondary)
            Text("Scanning loads near you…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s2)
    }

    private var locationDeniedState: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text("Enable location to see load intelligence near you.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s2)
    }

    private var emptyState: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
            Text(searchRadius.map { "No hot zones within \($0) mi right now." } ?? "No hot zones near you right now.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s2)
    }

    private func errorState(_ message: String) -> some View {
        #if DEBUG
        let _ = message
        #endif
        return HStack(spacing: Space.s2) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .symbolEffect(.pulse, options: .repeating)
            Text("Updating load intelligence…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Button { Task { await load() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry load intelligence")
        }
        .padding(.vertical, Space.s2)
    }

    private var footerMeta: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("ESANG · EusoTrip Intelligence")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let at = lastLoadedAt {
                Text("Updated " + HotZonesTime.shortAgo(from: at))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
            if loading && !opportunities.isEmpty {
                ProgressView().controlSize(.mini).tint(palette.textSecondary)
            }
        }
    }

    // MARK: Helpers

    /// Mirrors the server's demand-tier thresholds in `getActiveZones`
    /// (`loadToTruckRatio > 2.8 → CRITICAL`, `> 2.0 → HIGH`, else
    /// `ELEVATED`) so the near-me tile reads the same tier semantics as
    /// the national Hot Zones surface. No fabrication — purely a styling
    /// classification off the REAL ratio.
    private func demandTier(_ ratio: Double) -> String {
        if ratio > 2.8 { return "CRITICAL" }
        if ratio > 2.0 { return "HIGH" }
        return "ELEVATED"
    }

    private func prettyEquip(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil; locationDenied = false
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            locationDenied = true; loading = false; return
        }
        do {
            let result = try await EusoTripAPI.shared.hotZones.getDriverOpportunities(
                lat: coord.latitude, lng: coord.longitude
            )
            // Server already ranks by AI proximity; keep that order.
            self.opportunities = result.opportunities
            self.roleContext = result.roleContext
            self.searchRadius = result.searchRadius
            self.lastLoadedAt = Date()
            loading = false
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
        }
    }
}

// MARK: - CurrentRouteWidget (catalog widget id: "current_route")
//
// Active-route glance: origin → destination lane, distance, and pickup
// date sourced from the Load the home VM already fetched. No extra
// network call — pure display of vm.activeLoad.

struct CurrentRouteWidget: View {
    @Environment(\.palette) private var palette
    let load: Load?

    private var statusColor: Color {
        switch load?.status.lowercased() {
        case "in_transit":  return .green
        case "assigned":    return Brand.warning
        case "delivered":   return palette.textTertiary
        default:            return palette.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CURRENT ROUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let l = load {
                    Text(l.status.uppercased().replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(statusColor)
                }
            }
            if let l = load {
                Text(l.loadNumber)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                HStack(alignment: .center, spacing: 4) {
                    Text(l.pickupLocation?.cityState ?? "-")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(l.deliveryLocation?.cityState ?? "-")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    Image(systemName: "road.lanes")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(l.distanceValue > 0 ? "\(Int(l.distanceValue)) mi" : "- mi")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(l.pickupDate ?? "-")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            } else {
                Text("No active route. Accept a tender to populate.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent blue→magenta outline +
        // ambient glow (dark) replacing the flat bgCard + faint-border
        // washout, bringing this tile up to the SVG card language.
        .eusoCard(radius: Radius.lg)
    }
}

// MARK: - Screen wrapped in Shell + Driver nav

/// Which tab is currently selected from the BottomNav. The Driver nav has
/// four slots (home/trips/wallet/me) with the center slot reserved for the
/// ESANG orb, which opens the ESANG chat rather than switching tabs.
/// SINGLE SOURCE OF TRUTH for the Driver bottom-nav tabs (label + SF Symbol).
/// Screens MUST build their nav slots from these computed properties, e.g.
///   NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: …)
/// Do NOT hardcode nav labels/icons inside a screen — that caused the
/// Wallet→Loads label drift and the Trips icon drift (swept 2026-05-22).
/// Renaming a tab here now propagates to every screen automatically.
enum DriverTab: String, CaseIterable, Identifiable {
    case home, trips, wallet, me
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home:   return "Home"
        case .trips:  return "Trips"
        case .wallet: return "Loads"   // case kept as .wallet for back-compat;
                                        // slot 3 is now the My Loads surface.
        case .me:     return "Me"
        }
    }
    var systemImage: String {
        switch self {
        case .home:   return "house"
        case .trips:  return "truck.box"
        case .wallet: return "shippingbox.fill"  // was "creditcard"; routes to DriverLoadsPane.
        case .me:     return "person"
        }
    }
}

struct DriverHomeScreen: View {
    let theme: Theme.Palette

    @State private var currentTab: DriverTab = .home
    @State private var orbState: OrbeSang.State = .idle
    /// The ESANG coach is presented as a custom overlay (not a system sheet)
    /// so we can drive a unified dissolve-to-orb transform on close — the
    /// sheet shrinks + blurs toward the orb while a single particle field
    /// converges on the same point. Web-parity behavior from the
    /// eSangChatWidget dissolve pattern.
    @State private var showeSang: Bool = false
    /// Drives the dissolve animation on close. While true, the sheet is
    /// scaling + blurring toward the orb anchor and particles are flying
    /// inward. Flips back to false after the burst clears.
    @State private var esangDissolving: Bool = false
    /// Particles spawn from this rect (the sheet's visual bounds). Captured
    /// once when the dissolve starts so the particle overlay can outlive the
    /// collapsing sheet.
    @State private var esangSheetRect: CGRect = .zero
    /// Orb anchor in screen space. Recomputed by `GeometryReader` so the
    /// dissolve always converges on the real orb position.
    @State private var orbAnchor: CGPoint = .zero
    /// True while the particle burst is actively rendering.
    @State private var esangBurstActive: Bool = false

    private func leadingSlots() -> [NavSlot] {
        [
            NavSlot(
                label: DriverTab.home.label,
                systemImage: DriverTab.home.systemImage,
                isCurrent: currentTab == .home,
                onTap: { currentTab = .home }
            ),
            NavSlot(
                label: DriverTab.trips.label,
                systemImage: DriverTab.trips.systemImage,
                isCurrent: currentTab == .trips,
                onTap: { currentTab = .trips }
            )
        ]
    }
    private func trailingSlots() -> [NavSlot] {
        [
            NavSlot(
                label: DriverTab.wallet.label,
                systemImage: DriverTab.wallet.systemImage,
                isCurrent: currentTab == .wallet,
                onTap: { currentTab = .wallet }
            ),
            NavSlot(
                label: DriverTab.me.label,
                systemImage: DriverTab.me.systemImage,
                isCurrent: currentTab == .me,
                onTap: { currentTab = .me }
            )
        ]
    }

    var body: some View {
        ZStack {
            Shell(theme: theme) {
                Group {
                    switch currentTab {
                    case .home:   DriverHome()
                    case .trips:  DriverTripsPane()
                    case .wallet: DriverLoadsPane()
                    case .me:     DriverMePane()
                    }
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: currentTab)
            } nav: {
                BottomNav(leading: leadingSlots(),
                          trailing: trailingSlots(),
                          orbState: orbState,
                          onTapOrb: { openeSang() })
            }

            // ESANG coach sheet — presented as a custom overlay so we can
            // animate the sheet itself shrinking + blurring toward the orb
            // on close, with particles that converge on the same point.
            if showeSang {
                esangBackdrop
                    .transition(.opacity)
                    .zIndex(90)

                esangSheet
                    .zIndex(91)
            }

            // Particle dissolve — spawns from the sheet's visual bounds
            // and converges on the orb, timed to land with the sheet's
            // shrink/blur collapse. NO transition: particles must be
            // fully opaque from the instant they spawn, otherwise the
            // view fades in while particles are already mid-flight and
            // the burst reads as empty.
            if esangBurstActive {
                eSangParticleBurst(
                    sourceRect: esangSheetRect,
                    anchor: orbAnchor,
                    duration: 0.65,
                    onDone: { esangBurstActive = false }
                )
                .frame(width: Device.width, height: Device.height)
                .allowsHitTesting(false)
                .zIndex(100)
            }
        }
        .onAppear { updateOrbAnchor() }
        // DriverHome's "Browse available loads" button fans out this
        // event when the driver is between loads and wants the full
        // Eusoboards view. The home pane doesn't own tab state, so we
        // listen here and swap the BottomNav selection.
        .onReceive(NotificationCenter.default.publisher(for: .eusoSwitchToTripsTab)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                currentTab = .trips
            }
        }
    }

    // MARK: - ESANG orchestration

    private func openeSang() {
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()
        orbState = .thinking
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)) {
            showeSang = true
        }
    }

    /// Kicks off the dissolve: the sheet's in-place scale+blur collapse and
    /// the particle burst start on the SAME frame so the motion reads as
    /// one graceful transform. Matches the web twin's 0.5s collapse with a
    /// 0.15s particle tail (total 0.65s window).
    private func dissolveeSang() {
        guard showeSang, !esangDissolving else { return }
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        // Recapture the anchor + sheet rect right now so the burst is
        // guaranteed to have non-zero coordinates, even if onAppear
        // hadn't fired yet or the device metrics changed.
        updateOrbAnchor()
        // Particles must render fully opaque from frame zero — so flip
        // the burst flag OUTSIDE withAnimation (no fade-in transition).
        // The sheet's scale+blur+opacity collapse animates alongside.
        // Both state changes commit on the same render tick because
        // SwiftUI batches state updates within one function body.
        esangBurstActive = true
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.5)) {
            esangDissolving = true
        }
        // Unmount the sheet after the particle tail lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            showeSang = false
            esangDissolving = false
            orbState = .idle
        }
    }

    private func updateOrbAnchor() {
        // The Shell is a fixed-size device frame centered in its parent —
        // the orb sits horizontally centered and just above the bottom
        // safe-area/nav plate. We compute the anchor in the Shell's local
        // space, which is also the ZStack's space (same parent).
        orbAnchor = CGPoint(
            x: Device.width / 2,
            y: Device.height - Device.safeBottom - Device.navHeight / 2 - Space.s2
        )
        // The sheet's bounds equal the Shell bounds minus the top and bottom
        // insets that the sheet itself will pad. For particle seeding we use
        // roughly the sheet's visible chrome area so particles spawn "from
        // the chat box" rather than from safe-area padding.
        esangSheetRect = CGRect(
            x: 0,
            y: Device.safeTop,
            width: Device.width,
            height: Device.height - Device.safeTop - Device.safeBottom - Device.navHeight
        )
    }

    // MARK: - ESANG overlay subviews

    private var esangBackdrop: some View {
        // Dim layer behind the sheet. Tapping outside starts the dissolve —
        // matches the web "tap out to close" affordance.
        Color.black
            .opacity(esangDissolving ? 0 : 0.45)
            .frame(width: Device.width, height: Device.height)
            .onTapGesture { dissolveeSang() }
            .animation(.easeOut(duration: 0.5), value: esangDissolving)
    }

    private var esangSheet: some View {
        // Match the web twin (eSangChatWidget.tsx line 717–720):
        //   animate: { opacity: 0, scale: 0.15, filter: 'blur(12px)', y: 0 }
        //
        // The sheet shrinks + blurs in place — it does NOT translate toward
        // the orb. The particle burst carries the visual motion so there's
        // one coherent transform, not two competing motions.
        return DrivereSangCoachSheet(onClose: dissolveeSang)
            .environment(\.palette, theme)
            .frame(width: Device.width, height: Device.height)
            .background(theme.bgPage)
            .clipShape(RoundedRectangle(cornerRadius: 55, style: .continuous))
            .scaleEffect(esangDissolving ? 0.15 : 1.0)
            .blur(radius: esangDissolving ? 12 : 0)
            .opacity(esangDissolving ? 0 : 1)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                )
            )
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by DriverHome's "Browse available loads" CTA and caught by
    /// DriverHomeScreen to swap the BottomNav selection to the Trips
    /// tab (which hosts the Eusoboards board).
    static let eusoSwitchToTripsTab = Notification.Name("eusoSwitchToTripsTab")
}

// MARK: - SuggestedLoadCard

/// Compact card used by the Home carousel of available freight shown
/// when the driver has no active assignment. Smaller than the full
/// Eusoboards `LoadBoardCard` — the driver has to be able to swipe
/// through a stack of them at a glance, so we show the lane, rate, and
/// one meta line (equipment + pickup window) and hide the broker row
/// + action buttons. Tapping the card routes the selection to
/// `LoadDetailSheet` for the full breakdown.
struct SuggestedLoadCard: View {
    let load: AvailableLoad
    @Environment(\.palette) var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Top meta — equipment + hot chip + ID tag
            HStack(spacing: Space.s2) {
                StatusPill(text: load.equipment,
                           kind: load.hazmat ? .hazmat : .info)
                if load.hotScore >= 4 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("HOT")
                            .font(EType.micro).tracking(0.6)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
                Spacer(minLength: 0)
                Text(load.id)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }

            // Lane
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PICKUP")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(load.origin)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
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
                        .lineLimit(1)
                }
            }

            Divider().overlay(palette.borderFaint)

            // Rate + window
            HStack(alignment: .firstTextBaseline) {
                Text("$\(Int(load.rate).formatted())")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text(String(format: "$%.2f/mi", load.rpm))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }

            HStack(spacing: Space.s2) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text(load.pickupWindow)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Previews (both themes)

#Preview("Driver Home · Dark") {
    DriverHomeScreen(theme: Theme.dark)
        .environmentObject(DriverProfileStore())
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Driver Home · Light") {
    DriverHomeScreen(theme: Theme.light)
        .environmentObject(DriverProfileStore())
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}

// MARK: - D-1 post-truck hero glyphs (drawn Paths — no SF Symbol on the slab)

/// Concentric arcs sweeping toward the radar — "offers travelling to you".
private struct PostTruckHeroArcs: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: r.maxX - 30, y: r.midY)
        for i in 1...4 {
            let radius = CGFloat(i) * 22
            p.addArc(center: center, radius: radius,
                     startAngle: .degrees(120), endAngle: .degrees(240),
                     clockwise: false)
        }
        return p
    }
}

/// A radar/visibility glyph — concentric rings + a sweep tick. Signals
/// "you are visible / brokers can see you".
private struct PostTruckRadarGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: r.insetBy(dx: 1, dy: 1))
        p.addEllipse(in: r.insetBy(dx: r.width * 0.28, dy: r.height * 0.28))
        p.move(to: CGPoint(x: r.midX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY + 2))
        return p
    }
}
