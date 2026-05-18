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
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Screen

struct DriverHome: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var profile: DriverProfileStore
    @StateObject private var vm = DriverHomeViewModel()
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
                // TileStack wraps Home's hero sections so each one fades
                // and lifts into place in source order (weather → active
                // card → metric row → recent section) — matches the web
                // platform's tile load-in on /driver/home.
                TileStack(alignment: .leading, spacing: Space.s5) {
                    switch vm.phase {
                    case .idle, .loading:
                        loadingState
                    case .loaded:
                        if vm.isOffline { offlineBanner }
                        // ESANG Morning Brief — top coaching card from
                        // the driver's role+vertical+hazmat-aware feed.
                        eSangMorningBriefCard()
                        // 75th firing (2026-04-24, hygiene + fallback C):
                        // render live WeatherCard ONLY when WeatherKit
                        // resolved a real snapshot for the driver's real
                        // coordinate. When location is denied/restricted
                        // we render a neutral gradient CTA to open
                        // Settings — no fabricated tempF/windMph/visibility.
                        // When WeatherKit is authorized but momentarily
                        // unavailable, we silently omit the card rather
                        // than flash an error — matches the §13 "neutral
                        // empty state on the client, no fake data" rule.
                        if let w = vm.weather {
                            WeatherCard(snapshot: w)
                        } else if vm.weatherAvailability == .needsLocation {
                            enableLocationCard
                        }
                        // Pre-trip DVIR status — 49 CFR 396.11. Only
                        // surfaces when the driver actually has an
                        // upcoming / active load assigned, since a
                        // pre-trip outside of that window isn't
                        // actionable from the Home glance. Silent
                        // otherwise (returns EmptyView from body).
                        if vm.activeLoadSummary != nil || vm.activeLoad != nil {
                            PreTripDVIRStatusPill()
                        }
                        if vm.activeLoadSummary != nil || vm.activeLoad != nil {
                            activeLoadCard
                        } else {
                            noActiveLoadCard
                        }
                        metricRow
                        // The Haul weekly progress — XP ring + active
                        // mission count + rank, routes into 060 dashboard.
                        TheHaulWeeklyTile()
                        // Compliance countdown — CDL / medical / hazmat
                        // / TWIC / permits expiring inside 60 days.
                        // Silent (EmptyView) when nothing is expiring.
                        ComplianceCountdownStrip()
                        // Driver Intel rotating headline widget — 15-article
                        // carousel (10 s rotation) backed by NewsFeedStore.
                        // Sits between the metric row and the recent-activity
                        // list so the dashboard gains a glanceable news
                        // surface without pushing the recents below the fold.
                        NewsCarouselWidget()
                        recentSection
                        // National Hot Zones intelligence widget — pulls
                        // the same `hotZones.getRateFeed` the web
                        // platform's /hot-zones page uses so the driver
                        // sees live load-to-truck ratios, rate surges,
                        // and demand tiers, with an interactive HERE
                        // heatmap and a horizontal carousel of the
                        // hottest zones. Sits under the recent section
                        // per 2026-04-22 direction.
                        HotZonesWidget()
                    case .error(let message):
                        errorState(message)
                        metricRow
                        NewsCarouselWidget()
                        HotZonesWidget()
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
            .refreshable {
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
        // Load Details sheet for the active/assigned load. Reuses the
        // canonical LoadDetailSheet the Eusoboards surface renders so
        // drivers get the same route map, rate breakdown, and broker
        // card regardless of which surface opened it.
        .sheet(isPresented: $showAssignedLoadDetail) {
            if let load = vm.activeLoad {
                LoadDetailSheet(
                    load: AvailableLoad.from(
                        load,
                        originCity: vm.originCity,
                        destCity: vm.destCity
                    )
                )
                .environment(\.palette, palette)
                .eusoSheetX()
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
                        equipment: "—",
                        rate: 0,
                        rpm: 0,
                        pickupWindow: vm.pickupStatusPill,
                        broker: "Dispatch",
                        hazmat: false,
                        weight: "—",
                        hotScore: 0,
                        originLat: 39.8283, originLng: -98.5795,
                        destLat: 39.8283, destLng: -98.5795
                    )
                )
                .environment(\.palette, palette)
                .eusoSheetX()
            }
        }
        // HOS port — full 019 surface with banks / 24h timeline / 3-meter
        // strip. Picks the `.afternoon` register so the live status reads
        // as an in-shift break state instead of the night scenario.
        .sheet(isPresented: $showHosSheet) {
            HosDutyStatus(register: .afternoon)
                .environment(\.palette, palette)
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
        .sheet(item: $selectedSuggestedLoad) { load in
            LoadDetailSheet(load: load)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    // MARK: TopBar

    // Figma 212:444 — two-line display greeting left, uppercase right-column label,
    // chat round button with magenta iridescent badge dot.
    private var topBar: some View {
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

            // Right-rail greeting + location — two tight lines, no mid-dot,
            // with a small gradient pin glyph under a clean caps "GOOD
            // AFTERNOON". Prior single-line mid-dot layout forced a 3-line
            // wrap in a 110pt frame that read as cramped.
            VStack(alignment: .trailing, spacing: 4) {
                Text(timeOfDayGreeting.uppercased())
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
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

    private var timeOfDayGreeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    // MARK: Loading / empty / error states

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

    /// Subtle strip shown above the active-load card when the live backend
    /// was unreachable and the view fell back to the on-device demo state.
    /// Keeps the dashboard fully usable while being honest about the state.
    private var offlineBanner: some View {
        HStack(spacing: Space.s2) {
            Circle()
                .fill(Brand.warning)
                .frame(width: 6, height: 6)
            Text("Offline preview")
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
                UIApplication.shared.open(url)
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
                    Text("Grant location access to see local conditions, visibility, and route weather alerts.")
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
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
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
                    Text("Quiet on your lane — we'll let you know the moment tenders land.")
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
                                selectedSuggestedLoad = load
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
                    Text("Backend unavailable")
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
                        if vm.cargoWeightPill != "—" {
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
                    Button("Review load brief") { showAssignedLoadDetail = true }
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

    // MARK: Metric row — Figma 212:444 two tiles
    // HOS uses split-gradient numeral (7h blue / 22m magenta) with mini unit suffixes.
    // Wallet shows plain white bold numeral ($4,118 when wired).

    private var metricRow: some View {
        // 3-meter §395.3 HOS strip per the Light/Dark PNG canon
        // (`01 Driver/{Light,Dark}/010 Driver Home.png`):
        //   DRIVE     · §395.3(a)(3)(i) 11-hour drive limit
        //   ON-DUTY   · §395.3(a)(2) 14-hour on-duty window
        //   CYCLE     · §395.3(b) 70-hour/8-day or 60-hour/7-day cycle
        // The full row tap-target opens the HOS Duty Status port screen
        // (019_HosDutyStatus) where the same three meters render with live
        // banks + 24h timeline + per-segment log entries. Wallet moved off
        // the Home metric row — still reachable via bottom-nav Wallet tab
        // and from per-row deep-links in the Recent activity card below.
        Button {
            showHosSheet = true
        } label: {
            HStack(spacing: Space.s3) {
                HosTile(value: vm.hosDriveLeftDisplay, label: "DRIVE")
                HosTile(value: vm.hosOnDutyDisplay,    label: "ON-DUTY")
                HosTile(value: vm.hosCycleDisplay,     label: "CYCLE")
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hours of service. Drive \(vm.hosDriveLeftDisplay). On-duty \(vm.hosOnDutyDisplay). Cycle \(vm.hosCycleDisplay).")
        .accessibilityHint("Opens the HOS duty status port")
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
                            Text("Assignments, duty changes, and payouts will show up here.")
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

    /// Parse "7h 22m" → (hours, minutes). Falls back gracefully on "—" / bad input.
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

// MARK: - Screen wrapped in Shell + Driver nav

/// Which tab is currently selected from the BottomNav. The Driver nav has
/// four slots (home/trips/wallet/me) with the center slot reserved for the
/// ESANG orb, which opens the ESANG chat rather than switching tabs.
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
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Driver Home · Light") {
    DriverHomeScreen(theme: Theme.light)
        .environmentObject(DriverProfileStore())
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
