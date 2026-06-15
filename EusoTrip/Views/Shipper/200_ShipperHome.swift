//
//  200_ShipperHome.swift
//  EusoTrip — Shipper · Home (brick 200).
//
//  Parity-reconciled to `02 Shipper/Code/200_ShipperHome.swift` per
//  _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar greeting (time-of-day + signed-in user's first name +
//  monogram avatar w/ unread dot), IridescentHairline, gradient-rim
//  attention card, 4-stat strip (Active · Bids · Rate/mi · On-time),
//  8-stage lifecycle strip per active row, eSang strip.
//
//  Real data preserved: every store wiring kept — `shippers.{getDashboardStats,
//  getLoadsRequiringAttention, getActiveLoads, getRecentLoads, getProfile}` via
//  the existing ShipperDashboardStore / ShipperAlertsStore /
//  ShipperActiveLoadsStore / ShipperRecentLoadsStore / ShipperProfileStore.
//
//  ZERO-FABRICATION (2026-06-06): no hard-coded persona, company, or
//  invented metric anywhere at runtime. The header company name binds to
//  the signed-in user's `shippers.getProfile.companyName` (NEVER a founder
//  default); active-load / pending-bid / attention counts bind to the
//  real `shippers.getDashboardStats` + `getLoadsRequiringAttention`
//  envelopes; no-source values render an honest "—". No `?? <invented>`
//  number/string survives — only `?? "—"` sentinels remain.
//  Web peer: ShipperDashboard.tsx (`/shipper/dashboard`).
//
//  BottomNav: out of scope per parity mandate §1 (Home / Create Load /
//  Loads / Me — already matches user-feedback doctrine).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct ShipperHome: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var dashboard = ShipperDashboardStore()
    @StateObject private var alerts    = ShipperAlertsStore()
    @StateObject private var active    = ShipperActiveLoadsStore()
    @StateObject private var recent    = ShipperRecentLoadsStore()
    /// Rate-per-mile + on-time aggregates derived from REAL procs —
    /// `shippers.getMyLoads` (rate ÷ distance over the shipper's actual
    /// load rows) and `shippers.getCatalystPerformance` (server-computed
    /// on-time SQL, weighted across catalysts). The slim
    /// `shippers.getDashboardStats` envelope hardcodes both to 0
    /// (server WIRE-GAP), so without this store the two stat tiles
    /// rendered a permanent em-dash.
    @StateObject private var aggregates = ShipperHomeAggregatesStore()
    // Real company identity for the header subhead — `shippers.getProfile`
    // (companyName). NEVER a founder default; empty/unavailable → "—".
    @StateObject private var profile   = ShipperProfileStore()
    // EUSO-2057 — gates the DU avatar's unread dot on real messaging
    // unread count via the existing project-wide store.
    @ObservedObject private var unread = UnreadMessageStore.shared

    /// Founder mandate 2026-05-05: every role's home gets the same
    /// top-right messages affordance. Tapping presents `MessagesScreen`
    /// as a full-screen cover (NOT a pull-up sheet) so the shipper
    /// lands on the real inbox + can drill into a thread + start a new
    /// conversation, matching the web platform's messaging surface.
    @State private var showMessages: Bool = false

    // Real weather snapshot (CoreLocation + WeatherKit → NWS → Open-Meteo
    // cascade in WeatherService). nil → render the "Enable location"
    // CTA when CoreLocation is .notDetermined / .denied / .restricted,
    // or render nothing when authorized but momentarily unavailable.
    // Per home-widget doctrine the weather card sits between the
    // attention card and the CTA row across every role.
    @State private var weather: WeatherSnapshot? = nil
    /// Collapsible state for the attention card. Founder ask
    /// 2026-05-07: 'loads requiring attention on home screen needs
    /// to be hideable. not just stretched out no matter what. let
    /// it be collapsable in a graceful manner.' Default expanded so
    /// the user sees the urgent context on first paint; persisted
    /// via UserDefaults so the user's choice carries across sessions.
    @State private var attentionExpanded: Bool = (UserDefaults.standard.object(forKey: "shipper.home.attentionExpanded") as? Bool) ?? true
    /// Mirrors `DriverHomeViewModel.WeatherAvailability` — same four
    /// states (.pending / .live / .needsLocation / .unavailable) so
    /// the shipper home renders the same enable-location CTA the
    /// driver home does. Founder report 2026-05-05 — "the app
    /// doesn't ask for my location so it doesn't load the weather
    /// widget for shipper or driver role".
    @State private var weatherNeedsLocation: Bool = false
    /// The signed-in user's avatar photo (users.profilePicture, stored as a
    /// base64 data URL by profile.updateAvatar). Fetched on appear + on
    /// .eusoProfileUpdated; duAvatar renders it, falling back to initials.
    @State private var avatarImage: UIImage? = nil

    // ── Home-widget customization ─────────────────────────────────────
    // Founder bug 2026-06-02 — "there is no resizing the widget capability
    // you said you did on homescreen". The shared HomeWidgetGrid DOES carry
    // a span/resize engine, but the shipper catalog rows
    // (HomeWidgetCatalog.shipper, owned by 010_DriverHome) all declare a
    // single `[.full]` span, so its edit-mode size picker never appeared on
    // the shipper home. Rather than reach into another file's catalog, the
    // shipper home now owns a bespoke `ShipperWidgetBoard` that surfaces a
    // real per-widget size chooser (Compact · Half · Full) on EVERY tile and
    // honors the chosen span in the rendered layout — while persisting to
    // the *same* UserDefaults cache key + the *same* `users.{get,save}
    // DashboardLayout` slot shape the shared grid uses, so the size survives
    // relaunch and stays cross-platform with web's 12-col w/h model.
    private let widgetLayoutKey = "shipper.home.widgetOrder"

    /// Canonical secondary widgets + the spans each may resize to. Every
    /// shipper tile is span-aware (reads `\.homeWidgetSpan`), so all three
    /// sizes are offered. `.full` is always the seed.
    private let shipperWidgetSlots: [ShipperWidgetBoard.Slot] = [
        .init(id: "activeLoads",      sizes: [.full, .compact]),
        .init(id: "esang",            sizes: [.full, .half, .compact]),
        .init(id: "spend_summary",    sizes: [.full, .compact]),
        .init(id: "attention_alerts", sizes: [.full, .compact]),
        .init(id: "recent",           sizes: [.full, .compact]),
        .init(id: "news",             sizes: [.full, .half]),
    ]

    /// Per-tile renderer. The span arrives as an EXPLICIT parameter from
    /// ShipperWidgetBoard — NOT via `@Environment(\.homeWidgetSpan)` on
    /// ShipperHome itself. The previous environment read resolved against
    /// ShipperHome's OWN environment (always `.full`, since the board's
    /// `.environment(...)` modifier wraps the rendered tile, not this
    /// screen), which is why choosing "Compact" in the size picker changed
    /// nothing on screen — founder evidence 2026-06-11. Passing the span
    /// down the call chain makes every size tier actually re-layout.
    private func shipperHomeRender(_ id: String, _ span: HomeWidgetSpan) -> AnyView {
        switch id {
        case "activeLoads":       AnyView(activeLoadsSection(span))
        case "esang":             AnyView(esangStrip(span))
        case "spend_summary":     AnyView(spendSummaryWidget(span))
        case "attention_alerts":  AnyView(attentionAlertsWidget(span))
        case "recent":            AnyView(recentActivitySection(span))
        case "news":              AnyView(NewsCarouselWidget())
        default:                  AnyView(EmptyView())
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                VStack(alignment: .leading, spacing: Space.s5) {
                    // Founder ask 2026-05-07: weather widget pinned
                    // to the top of every role's home, everything
                    // else after.
                    weatherSection
                    // ESANG Morning Brief (Spark overnight) — Tier 1
                    // #21 ship 2026-05-21. Per home-widget doctrine
                    // sits between weather and the role-specific
                    // attention card.
                    SparkBriefCard(role: .shipper)
                    collapsibleAttentionCard
                    ctaRow
                    statRow
                    // Reorderable + RESIZABLE secondary-widget zone. The
                    // bespoke ShipperWidgetBoard surfaces a per-widget size
                    // chooser on every tile and packs the chosen spans into
                    // the single-column home, persisting across launches.
                    ShipperWidgetBoard(
                        slots: shipperWidgetSlots,
                        role: "SHIPPER",
                        storageKey: widgetLayoutKey,
                        render: { id, span in shipperHomeRender(id, span) }
                    )
                    Color.clear.frame(height: 96) // bottom-nav clearance
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        // After the user taps Allow / Deny on the iOS location
        // prompt, WeatherService posts this — re-run the dashboard
        // refresh so the weather card flips from the CTA into the
        // live snapshot without waiting for a manual pull.
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("eusoWeatherAuthorizationChanged"))) { _ in
            Task { await refreshAll() }
        }
        // RealtimeService → live updates from the shipper's load room
        // fan-out (carrier accept, driver assign, status changes)
        // refresh the home dashboard surface in real time.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await refreshAll() }
        }
        // Avatar changed (this device's upload posts .eusoProfileUpdated, or a
        // remote profile edit arrives via RealtimeService) — re-fetch the photo.
        .onReceive(NotificationCenter.default.publisher(for: .eusoProfileUpdated)) { _ in
            Task { await loadAvatar() }
        }
        .fullScreenCover(isPresented: $showMessages) {
            MessagesScreen()
                .environment(\.palette, palette)
        }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = dashboard.refresh()
        async let b: Void = alerts.refresh()
        async let c: Void = active.refresh()
        async let d: Void = recent.refresh()
        async let p: Void = profile.refresh()
        async let ag: Void = aggregates.refresh()
        async let av: Void = loadAvatar()
        async let w: WeatherSnapshot? = WeatherService.shared.fetchCurrent()
        let snap = await w
        _ = await (a, b, c, d, p, ag, av)
        weather = snap
        // Resolve CTA visibility from the post-fetch authorization
        // status so the home renders an "Enable location" affordance
        // when CoreLocation hasn't been asked yet (.notDetermined) or
        // when the user previously denied / restricted access.
        let status = WeatherService.shared.authorizationStatus
        weatherNeedsLocation = (snap == nil) && (
            status == .notDetermined ||
            status == .denied ||
            status == .restricted
        )
        unread.refresh()  // EUSO-2057: kicks UnreadMessageStore -> messaging.getUnreadCount
    }

    /// Live weather card driven by `WeatherService.shared.fetchCurrent()`
    /// (WeatherKit → NWS → Open-Meteo cascade, real CoreLocation fix).
    /// Renders nothing when the snapshot is nil — empty state per
    /// the no-mock-data doctrine. The shared `WeatherCard` view is
    /// the same component the driver dashboard uses, so the
    /// time-of-day fix in the card affects every role uniformly.
    @ViewBuilder
    private var weatherSection: some View {
        // Always-visible bespoke weather surface — owns its own fetch and
        // renders an honest state (data / loading / enable-location /
        // unavailable) so the widget never disappears on any role.
        HomeWeatherWidget()
    }

    /// "Enable location for live weather" CTA — same shape as the
    /// driver home's `enableLocationCard`. Tap behavior:
    ///   • `.notDetermined` → fire `requestPermissionIfNeeded()` and
    ///     re-fetch after the user responds (1s debounce gives iOS
    ///     time to record the new status before the retry).
    ///   • `.denied` / `.restricted` → open Settings since iOS won't
    ///     re-prompt.
    private var shipperEnableLocationCard: some View {
        Button {
            let status = WeatherService.shared.authorizationStatus
            if status == .notDetermined {
                WeatherService.shared.requestPermissionIfNeeded()
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await refreshAll()
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
            // Bespoke EusoCard surface — iridescent blue→magenta outline
            // + glow so the enable-location CTA reads as a first-class
            // card matching the SVG card language (mirrors DriverHome's
            // enableLocationCard treatment).
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
    }

    // MARK: - TopBar — eyebrow + counter + greeting + DU avatar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ SHIPPER · DASHBOARD")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(counterLine)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                    // Long names ("Christopherson") used to wrap into a
                    // third line that overlapped the avatar; the empty-
                    // name fallback produced no greeting at all because
                    // the hardcoded "Diego" only fit Diego. Now: trim +
                    // shrink-to-fit so every name renders cleanly, and
                    // fall back to "Welcome back" when no name is set.
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                // Top-right cluster — messages glyph then DU avatar.
                // Mirrors the driver home (010) header so muscle memory
                // carries between roles. The MessagesBadgeButton
                // already paints its own unread pill from the same
                // `UnreadMessageStore` the avatar's red dot reads, so
                // both surfaces stay in sync.
                HStack(spacing: 8) {
                    MessagesBadgeButton(showMessages: $showMessages, palette: palette)
                    duAvatar
                }
            }
            .padding(.top, Space.s2)
            Text(subhead)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    /// Identity-aware + time-of-day-aware greeting. "Good morning, <first>"
    /// / "Good afternoon, <first>" / "Good evening, <first>" per the local
    /// hour, where <first> is the SIGNED-IN user's first name from the
    /// session. When the session has no first name we drop the comma-tail
    /// entirely so the headline reads as a clean "Good morning" — never a
    /// hardcoded persona (the previous hardcoded fallback shipped a fixed
    /// name to every cold-start screen, the "discombobulated welcome back"
    /// the user flagged 2026-05-04).
    /// Fetch the signed-in user's avatar (users.profilePicture, a base64 data
    /// URL written by profile.updateAvatar) via profile.getMyProfile and decode
    /// it for duAvatar. Cosmetic — any failure silently keeps the initials.
    private func loadAvatar() async {
        struct Out: Decodable { let avatar: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.queryNoInput("profile.getMyProfile")
            let img = Self.decodeAvatarDataURL(out.avatar)
            await MainActor.run { avatarImage = img }
        } catch {
            // Cosmetic — leave the initials fallback in place.
        }
    }

    private static func decodeAvatarDataURL(_ s: String?) -> UIImage? {
        guard let s, !s.isEmpty else { return nil }
        let b64 = s.contains(",") ? String(s.split(separator: ",").last ?? "") : s
        guard let data = Data(base64Encoded: b64), let img = UIImage(data: data) else { return nil }
        return img
    }

    private var headline: String {
        let first = (session.user?.firstName)
            .flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation: String
        switch hour {
        case 5..<12:  salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        case 17..<22: salutation = "Good evening"
        default:      salutation = "Welcome back"  // late-night / early-morning — neutral, no comma-tail
        }
        if let first { return "\(salutation), \(first)" }
        return salutation
    }

    /// Identity + counts subhead, e.g. "<Company> · 12 active loads · 2 need
    /// attention". Every value binds to a real proc; no-source segments
    /// render an honest "—" (NEVER a founder company or invented number).
    private var subhead: String {
        // Company name from the signed-in shipper's `shippers.getProfile`
        // envelope (companyName). Empty / unavailable → "—". The session
        // user (AuthUser) carries only `companyId`, not a human company name,
        // so the profile proc is the honest source — never a founder default.
        let company: String = {
            if let p = profile.state.value ?? nil,
               !p.companyName.trimmingCharacters(in: .whitespaces).isEmpty {
                return p.companyName
            }
            return "—"
        }()
        // Active-load count from `shippers.getDashboardStats`; no value yet → "—".
        let totalText: String = {
            if let s = dashboard.state.value ?? nil { return "\(s.activeLoads) active loads" }
            return "—"
        }()
        // Attention count from `shippers.getLoadsRequiringAttention`; not loaded → "—".
        let attentionText: String = {
            if case .loaded(let rows) = alerts.state { return "\(rows.count) need attention" }
            return "—"
        }()
        return "\(company) · \(totalText) · \(attentionText)"
    }

    /// Top-right counter band — "N ACTIVE · M BIDS PENDING" from
    /// `shippers.getDashboardStats` (activeLoads / pendingBids). Renders an
    /// honest "—" until the real envelope lands; no invented placeholder.
    private var counterLine: String {
        if let s = dashboard.state.value ?? nil {
            return "\(s.activeLoads) ACTIVE · \(s.pendingBids) BIDS PENDING"
        }
        return "—"
    }

    /// Signed-in user monogram on diagonal gradient + unread notification dot.
    /// AuthUser doesn't carry `initials` or unread-count; derive initials from
    /// the session user's real `name`. When no name is set we render a neutral
    /// person glyph — NEVER a founder monogram. Dot gated on real unread count.
    /// Tapping the avatar drills into the Me Home gateway (320), same as
    /// the bottom-nav Me tab. Without this Button the avatar paints but
    /// dead-taps — a known UX bug per founder feedback 2026-05-04.
    private var duAvatar: some View {
        // nil → no real name on the session, so render the person glyph
        // instead of fabricating initials.
        let initials: String? = {
            guard let n = session.user?.name?.trimmingCharacters(in: .whitespaces),
                  !n.isEmpty else { return nil }
            let parts = n.split(separator: " ").prefix(2).map(String.init)
            let chars = parts.compactMap { $0.first }.map(String.init)
            let derived = chars.joined().uppercased()
            return derived.isEmpty ? nil : derived
        }()
        return Button {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap, object: nil,
                userInfo: ["screenId": "320"]
            )
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let avatarImage {
                        // Uploaded photo (decoded from users.profilePicture's
                        // base64 data URL) with a brand-gradient ring.
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
                    } else {
                        Circle().fill(LinearGradient.diagonal)
                        if let initials {
                            Text(initials)
                                .font(.system(size: 14, weight: .bold)).tracking(0.4)
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 40, height: 40)

                // EUSO-2057: gated on UnreadMessageStore.shared.total
                // (messages.getUnreadCount). Hidden when zero unread.
                if unread.total > 0 {
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().fill(Brand.danger).frame(width: 7, height: 7))
                        .offset(x: 2, y: -2)
                        .accessibilityLabel("\(unread.total) unread")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Me")
        .accessibilityHint("Open your account, wallet, network and settings")
    }

    // MARK: - Attention card — gradient-rimmed, danger-washed top

    /// Wraps the existing attentionCard with a collapsible chrome —
    /// header always visible, body slides + fades on toggle. When
    /// the user collapses it, only the count + chevron remain so
    /// the home reclaims vertical space.
    @ViewBuilder
    private var collapsibleAttentionCard: some View {
        if case .loaded(let rows) = alerts.state, !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        attentionExpanded.toggle()
                    }
                    UserDefaults.standard.set(attentionExpanded, forKey: "shipper.home.attentionExpanded")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("LOADS REQUIRING ATTENTION")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textPrimary)
                        Text("\(rows.count)")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(LinearGradient.diagonal))
                        Spacer(minLength: 0)
                        Image(systemName: attentionExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                            .rotationEffect(.degrees(attentionExpanded ? 0 : 0))
                    }
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if attentionExpanded {
                    attentionCard
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        } else {
            // Loading / empty / error states still flow through the
            // original card so the user gets the same skeleton +
            // empty + error UX.
            attentionCard
        }
    }

    @ViewBuilder
    private var attentionCard: some View {
        switch alerts.state {
        case .loading:
            attentionShell { attentionSkeleton }
        case .loaded(let rows):
            if rows.isEmpty { EmptyView() }
            else { attentionShell { attentionRowsList(rows) } }
        case .empty:
            EmptyView()  // silence is the right empty for an alert feed
        case .error(let e):
            inlineError(e) { Task { await alerts.refresh() } }
        }
    }

    @ViewBuilder
    private func attentionShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // Real alert count from `shippers.getLoadsRequiringAttention`; any
        // non-loaded state shows 0 rather than an invented figure.
        let attentionCount: Int = {
            if case .loaded(let rows) = alerts.state { return rows.count }
            return 0
        }()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("Loads requiring attention")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(attentionCount)")
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(palette.tintDanger))
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(
                LinearGradient(colors: [Brand.danger.opacity(0.10),
                                        Brand.warning.opacity(0.10)],
                               startPoint: .leading, endPoint: .trailing)
            )

            content()
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Loads requiring attention, \(attentionCount)")
    }

    @ViewBuilder
    private func attentionRowsList(_ rows: [ShipperAPI.LoadAlert]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
            attentionRow(
                loadId: r.id,
                meta: "\(r.loadNumber) · \(r.message)",
                title: r.issue.uppercased()
            )
            if idx < rows.count - 1 { Divider().overlay(palette.borderFaint) }
        }
    }

    private func attentionRow(loadId: String, meta: String, title: String) -> some View {
        // Was a static HStack — both the "VIEW" pill and tapping the
        // row itself were dead-buttons (founder report 2026-05-06 —
        // "loads requiring attention the buttons are dead. i want
        // them to work, view doesnt do anything, it should show the
        // load"). Now wrapped in a Button that posts
        // `.eusoShipperLoadOpen`, which `ShipperLoadReceivers` (in
        // `RoleSurfaceRouter.swift`) already routes to screen 205
        // (Load Detail) with the captured loadId.
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperLoadOpen,
                object: nil,
                userInfo: ["loadId": loadId]
            )
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meta)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                Text("VIEW")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(Brand.danger)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(palette.tintDanger))
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .contentShape(Rectangle())   // makes the whole row hit-testable, not just the labels
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View load \(meta), \(title)")
    }

    private var attentionSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                Rectangle()
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .padding(.vertical, Space.s2)
                    .padding(.horizontal, Space.s4)
            }
        }
    }

    // MARK: - 2-CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Post a load") {
                NotificationCenter.default.post(name: .eusoShipperLoadCreate, object: nil)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Post a load, primary action")

            // Secondary CTA shape mirrors CTAButton's
            // `RoundedRectangle(cornerRadius: Radius.md)` so the two
            // buttons are visually balanced. Outline + bgCard
            // distinguishes secondary from the primary gradient pill.
            Button(action: {
                NotificationCenter.default.post(name: .eusoShipperBrowseCarriers, object: nil)
            }) {
                Text("Browse carriers")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 4-stat strip — Active · Bids · Rate/mi · On-time

    @ViewBuilder
    private var statRow: some View {
        switch dashboard.state {
        case .loading:
            statSkeleton
        case .loaded(let maybe):
            if let s = maybe { statTiles(s) } else { statTiles(emptyStats) }
        case .empty:
            statTiles(emptyStats)
        case .error(let e):
            inlineError(e) { Task { await dashboard.refresh() } }
        }
    }

    private func statTiles(_ s: ShipperAPI.DashboardStats) -> some View {
        // Trails are honest descriptors only — the dashboard envelope carries
        // no period-over-period delta, so we never fabricate "+3 this wk" /
        // "−6% vs Mar" / "+1.2 pts" trend numerals. Each metric value itself
        // binds to a real `shippers.getDashboardStats` field — except
        // rate/mi + on-time, which that envelope hardcodes to 0 (server
        // WIRE-GAP); those two bind to ShipperHomeAggregatesStore's real
        // derivations (`getMyLoads` rate÷distance, `getCatalystPerformance`
        // weighted on-time). Dashboard value still wins if the server ever
        // starts emitting a non-zero figure.
        HStack(spacing: Space.s2) {
            statTile(label: "Active", value: "\(s.activeLoads)",
                     trail: "in flight",
                     trailColor: palette.textSecondary)
            statTile(label: "Bids pending", value: "\(s.pendingBids)",
                     trail: "awaiting award",
                     trailColor: palette.textSecondary)
            statTile(label: "Rate / mi", value: rateValue(resolvedRatePerMile(s)),
                     trail: "avg",
                     trailColor: palette.textSecondary,
                     gradientNumeral: true, valueSize: 22)
            statTile(label: "On-time", value: percentValue(resolvedOnTimeRate(s)),
                     trail: "delivery rate",
                     trailColor: palette.textSecondary,
                     gradientNumeral: true)
        }
    }

    /// Real rate/mi — prefer the dashboard envelope when the server emits a
    /// non-zero value; otherwise the aggregate derived from the shipper's
    /// actual load rows (Σ rate ÷ Σ distance via `shippers.getMyLoads`).
    /// 0 when neither source has data → renders an honest em-dash.
    private func resolvedRatePerMile(_ s: ShipperAPI.DashboardStats) -> Double {
        if s.ratePerMile > 0 { return s.ratePerMile }
        return (aggregates.state.value ?? nil)?.ratePerMile ?? 0
    }

    /// Real on-time fraction (0–1) — dashboard envelope first, then the
    /// load-weighted `shippers.getCatalystPerformance` aggregate (server
    /// computes on-time per catalyst via actual vs estimated delivery SQL).
    private func resolvedOnTimeRate(_ s: ShipperAPI.DashboardStats) -> Double {
        if s.onTimeRate > 0 { return s.onTimeRate }
        return (aggregates.state.value ?? nil)?.onTimeRate ?? 0
    }

    private var statSkeleton: some View {
        HStack(spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 86)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func statTile(label: String, value: String,
                          trail: String, trailColor: Color,
                          gradientNumeral: Bool = false,
                          valueSize: CGFloat = 28) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                if gradientNumeral {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            .font(.system(size: valueSize, weight: .semibold).monospacedDigit())
            Text(trail).font(EType.caption).foregroundStyle(trailColor).lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Bespoke EusoCard surface — iridescent rim + glow per stat tile,
        // matching the SVG's lit stat strip and the DriverHome metric idiom.
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - Active loads — list of in-flight rows w/ 8-stage strip

    @ViewBuilder
    private func activeLoadsSection(_ span: HomeWidgetSpan) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Active loads".uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if case .loaded(let rows) = active.state {
                    Button("See all (\(rows.count))") {
                        NotificationCenter.default.post(name: .eusoShipperLoadListOpen, object: nil)
                    }
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                }
            }
            switch active.state {
            case .loading:
                activeLoadsSkeleton
            case .loaded(let rows):
                if rows.isEmpty {
                    activeLoadsEmptyState
                } else {
                    activeLoadsList(rows, span: span)
                }
            case .empty:
                activeLoadsEmptyState
            case .error(let e):
                inlineError(e) { Task { await active.refresh() } }
            }
        }
    }

    /// Smart empty state for the Active Loads card.
    ///
    /// `shippers.getActiveLoads` (line 9371 of EusoTripAPI.swift) only
    /// returns loads in IN-FLIGHT statuses (accepted / in_transit /
    /// dispatched / etc.) — NOT `posted`. But the dashboard counter
    /// (`shippers.getDashboardStats.activeLoads`) DOES include posted.
    /// So a shipper with 50 posted loads + 0 in-transit gets a "No
    /// active loads" message even though the eyebrow says
    /// "12 ACTIVE · 7 BIDS PENDING". That mismatch was confusing.
    ///
    /// New behavior: when dashboard.activeLoads > 0 but the in-flight
    /// list is empty, render a real CTA pointing the user to 201
    /// Loads where `shippers.getMyLoads` returns the full set
    /// (posted + in-flight). When the dashboard is also 0, fall
    /// through to the original "post a load" prompt.
    @ViewBuilder
    private var activeLoadsEmptyState: some View {
        let dashStats: ShipperAPI.DashboardStats? = dashboard.state.value ?? nil
        let dashActive = dashStats?.activeLoads ?? 0
        if dashActive > 0 {
            Button {
                NotificationCenter.default.post(
                    name: .eusoShipperLoadListOpen, object: nil
                )
            } label: {
                VStack(spacing: Space.s2) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("\(dashActive) loads awaiting carriers")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                    Text("Tap to see your full loads board.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s5)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            EusoEmptyState(
                systemImage: "shippingbox",
                title: "No active loads",
                subtitle: "Post a load to see it move here in real time."
            )
        }
    }

    private func activeLoadsList(_ rows: [ShipperAPI.ActiveLoad], span: HomeWidgetSpan) -> some View {
        // `.compact` span → glance at the single most-urgent load; `.full`
        // span → the standard three-row stack.
        let cap = span == .compact ? 1 : 3
        return VStack(spacing: 0) {
            ForEach(Array(rows.prefix(cap).enumerated()), id: \.element.id) { idx, row in
                activeRowView(row)
                if idx < min(rows.count, cap) - 1 {
                    Divider().overlay(palette.borderFaint)
                }
            }
        }
        // Bespoke EusoCard surface — iridescent rim + glow wraps the
        // active-loads list, matching the SVG card stack + DriverHome.
        .eusoCard(radius: Radius.lg)
    }

    private var activeLoadsSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0)
                    .fill(palette.bgCardSoft)
                    .frame(height: 76)
                if i < 2 { Divider().overlay(palette.borderFaint) }
            }
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func activeRowView(_ row: ShipperAPI.ActiveLoad) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            modeGlyph(for: row)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(row.origin) → \(row.destination)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    // 2026-05-17 — Shipper Home active-load row mode
                    // badge. Sibling adoption to 218 Dispatch Control —
                    // both consume the same ShipperAPI.ActiveLoad
                    // projection so they light up together.
                    LoadModeBadge(modeRaw: row.transportMode,
                                  multiVehicleCount: row.multiVehicleCount,
                                  compact: true)
                }
                Text("\(row.loadNumber) · \(cargoLabel(for: row))")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                lifecycleStrip(filled: lifecycleStage(for: row))
                    .padding(.top, 2)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(row.status.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(statusStyle(row.status))
                if row.rate > 0 {
                    Text(dollars(row.rate))
                        .font(EType.bodyStrong).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .contentShape(Rectangle())
        .onTapGesture {
            NotificationCenter.default.post(
                name: .eusoShipperLoadOpen, object: nil,
                userInfo: ["loadId": row.id, "loadNumber": row.loadNumber]
            )
        }
    }

    /// Canonical 8-stage lifecycle strip: Posted → Bidding → Awarded →
    /// Pickup → In transit → Delivery → Paperwork → Closed.
    private func lifecycleStrip(filled: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<8, id: \.self) { i in
                Circle()
                    .frame(width: i == filled - 1 ? 6 : 5,
                           height: i == filled - 1 ? 6 : 5)
                    .foregroundStyle(i < filled
                                     ? AnyShapeStyle(LinearGradient.primary)
                                     : AnyShapeStyle(palette.textTertiary.opacity(0.32)))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func modeGlyph(for row: ShipperAPI.ActiveLoad) -> some View {
        let load = row.loadNumber.uppercased()
        let isHazmat = load.contains("UN") || row.status.lowercased().contains("hazmat")
        let isReefer = (cargoLabel(for: row).lowercased().contains("reefer")
                        || cargoLabel(for: row).lowercased().contains("berries"))
        if isHazmat {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.hazmat.opacity(0.16))
                Rectangle()
                    .stroke(Brand.hazmat, lineWidth: 1.6)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: 40, height: 40)
        } else if isReefer {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Brand.info, lineWidth: 1.6)
                    .frame(width: 22, height: 18)
            }
            .frame(width: 40, height: 40)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                Image(systemName: "shippingbox")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 40, height: 40)
        }
    }

    private func statusStyle(_ status: String) -> AnyShapeStyle {
        switch status.lowercased() {
        case let s where s.contains("transit") || s.contains("delivery") || s.contains("posted"):
            return AnyShapeStyle(LinearGradient.primary)
        case let s where s.contains("bid"):
            return AnyShapeStyle(Brand.warning)
        case let s where s.contains("late") || s.contains("delay"):
            return AnyShapeStyle(Brand.danger)
        default:
            return AnyShapeStyle(palette.textPrimary)
        }
    }

    private func cargoLabel(for row: ShipperAPI.ActiveLoad) -> String {
        // EUSO-2042 wired: server now projects `cargoSummary` from
        // unNumber + cargoType + commodity + weight. Falls back to
        // driver line when the load has no cargo metadata yet.
        if let s = row.cargoSummary, !s.isEmpty { return s }
        if let unc = row.unNumber, !unc.isEmpty {
            let parts = [unc, row.cargoType, row.weightDisplay].compactMap { $0 }
            return parts.joined(separator: " · ")
        }
        return row.driver.isEmpty ? "Awaiting driver" : "Driver: \(row.driver)"
    }

    private func lifecycleStage(for row: ShipperAPI.ActiveLoad) -> Int {
        switch row.status.lowercased() {
        case "posted":              return 1
        case "bidding":             return 2
        case "awarded", "assigned": return 3
        case "pickup":              return 4
        case "in_transit", "in transit": return 5
        case "delivery", "delivering":   return 6
        case "paperwork":           return 7
        case "closed", "delivered": return 8
        default:                    return 1
        }
    }

    // MARK: - eSang strip

    private func esangStrip(_ span: HomeWidgetSpan) -> some View {
        Button(action: {
            NotificationCenter.default.post(name: .eusoShippereSangOpen, object: nil)
        }) {
            HStack(spacing: span == .compact ? Space.s2 : Space.s3) {
                OrbeSang(state: .idle, diameter: span == .compact ? 24 : 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(esangHeadline)
                        .font(span == .compact ? EType.caption.weight(.semibold) : EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    // `.compact` → single-line glance (headline only).
                    if span != .compact {
                        Text(esangSubline)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(span == .compact ? Space.s2 : Space.s3)
            // Bespoke EusoCard surface — iridescent rim + glow on the
            // eSang strip so the AI signal row reads as a lit surface
            // (matches the SVG eSang panel + DriverHome treatment).
            .eusoCard(radius: Radius.lg)
        }
        .buttonStyle(.plain)
    }

    /// eSang strip headline — bound to the real `shippers.getDashboardStats`
    /// rate/mi target. No fabricated carrier-match count or invented target;
    /// when no real rate is present we render a neutral, honest prompt.
    private var esangHeadline: String {
        if let s = dashboard.state.value ?? nil, s.ratePerMile > 0 {
            return "Ask eSang to source carriers under your \(dollarsPerMile(s.ratePerMile))/mi target"
        }
        return "Ask eSang for carrier and rate insights"
    }
    /// eSang strip subline — bound to the real first active-load lane from
    /// `shippers.getActiveLoads`. No invented savings/OTR figures; when there
    /// is no active load we render a neutral CTA instead of a fake lane.
    private var esangSubline: String {
        if case .loaded(let rows) = active.state, let first = rows.first {
            return "\(first.origin) → \(first.destination)"
        }
        return "Tap to open eSang"
    }

    // MARK: - Recent activity (kept — EXTRA-OK per parity audit)

    @ViewBuilder
    private func recentActivitySection(_ span: HomeWidgetSpan) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RECENT ACTIVITY")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch recent.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "clock", title: "No recent activity",
                                   subtitle: "Once a load delivers, it'll show up here with the lane and rate.")
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(rows.prefix(span == .compact ? 1 : 3)) { recentRow($0) }
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "clock", title: "No recent activity",
                               subtitle: "Once a load delivers, it'll show up here with the lane and rate.")
            case .error(let e):
                inlineError(e) { Task { await recent.refresh() } }
            }
        }
    }

    private func recentRow(_ row: ShipperAPI.RecentLoad) -> some View {
        // Wrapped in a Button so the row actually opens Load Detail.
        // Was a static HStack — founder report 2026-05-06: "nothing in
        // recent activity is clickable. fix this." Same notification
        // path the Active Loads section uses (`eusoShipperLoadOpen`)
        // so `ShipperLoadReceivers` routes to screen 205 with the
        // captured loadId.
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperLoadOpen,
                object: nil,
                userInfo: [
                    "loadId":     row.id,
                    "loadNumber": row.loadNumber,
                ]
            )
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.loadNumber)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(row.origin) → \(row.destination)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.status.uppercased())
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    if !row.deliveredAt.isEmpty {
                        Text(row.deliveredAt)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(Space.s3)
            .contentShape(Rectangle())
            // Bespoke EusoCard surface — whisper-intensity iridescent
            // outline on each recent-activity row so the ledger reads as
            // lit nested cards rather than flat bordered boxes.
            .eusoRow(radius: Radius.md)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open load \(row.loadNumber), \(row.origin) to \(row.destination)")
    }

    // MARK: - Shared widgets

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func inlineError(_ error: Error, retry: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't load this card")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(error.localizedDescription)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: retry) {
                Text("Retry")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Formatters + canonical fallback values

    /// Honest zero envelope. Used only on the `.empty` edge (a nil from the
    /// network layer — the server otherwise returns real zeros when a shipper
    /// has no loads). Renders true zeros / em-dash sentinels, NEVER invented
    /// founder figures, so the strip never fabricates a number on no-source.
    private var emptyStats: ShipperAPI.DashboardStats {
        ShipperAPI.DashboardStats(
            activeLoads: 0,
            pendingBids: 0,
            deliveredThisWeek: 0,
            ratePerMile: 0,
            onTimeRate: 0,
            totalSpendThisMonth: 0
        )
    }

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
    private func dollarsPerMile(_ v: Double) -> String { String(format: "$%.2f", v) }
    private func percent(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    /// Honest rate/mi: renders the real value when the server has a non-zero
    /// rate, else an em-dash sentinel (no rate computed yet) rather than "$0.00".
    private func rateValue(_ v: Double) -> String { v > 0 ? dollarsPerMile(v) : "—" }
    /// Honest on-time percent: real value when present, else em-dash sentinel.
    private func percentValue(_ v: Double) -> String { v > 0 ? percent(v) : "—" }

    // MARK: - Spend summary widget

    @ViewBuilder
    private func spendSummaryWidget(_ span: HomeWidgetSpan) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SPEND SUMMARY")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch dashboard.state {
            case .loading:
                listSkeleton
            case .loaded(let maybe):
                if let s = maybe { spendTiles(s, span: span) } else { spendTiles(emptyStats, span: span) }
            case .empty:
                spendTiles(emptyStats, span: span)
            case .error(let e):
                inlineError(e) { Task { await dashboard.refresh() } }
            }
        }
    }

    @ViewBuilder
    private func spendTiles(_ s: ShipperAPI.DashboardStats, span: HomeWidgetSpan) -> some View {
        // On-time binds to the same resolved aggregate the 4-stat strip
        // uses (dashboard envelope first, then the real catalyst-
        // performance derivation) and renders an honest em-dash when no
        // source has data — the previous `percent(0)` printed a
        // fabricated-looking "0.0%" on every fresh account.
        if span == .compact {
            // Condensed glance row — single lit card with the three numbers
            // inline, so the widget shrinks to a one-line height.
            HStack(spacing: Space.s4) {
                compactStat(value: dollars(s.totalSpendThisMonth), label: "spend", gradient: true)
                Divider().frame(height: 22).overlay(palette.borderFaint)
                compactStat(value: "\(s.pendingBids)", label: "bids", gradient: false)
                Divider().frame(height: 22).overlay(palette.borderFaint)
                compactStat(value: percentValue(resolvedOnTimeRate(s)), label: "on-time", gradient: true)
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
        } else {
            HStack(spacing: Space.s2) {
                statTile(label: "This month",  value: dollars(s.totalSpendThisMonth),
                         trail: "total spend",    trailColor: palette.textSecondary,
                         gradientNumeral: true, valueSize: 18)
                statTile(label: "Bids open",   value: "\(s.pendingBids)",
                         trail: "awaiting award", trailColor: palette.textSecondary)
                statTile(label: "On-time",     value: percentValue(resolvedOnTimeRate(s)),
                         trail: "delivery rate",  trailColor: Brand.success,
                         gradientNumeral: true)
            }
        }
    }

    /// Inline number+label used by the `.compact` spend strip.
    private func compactStat(value: String, label: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Group {
                if gradient { Text(value).foregroundStyle(LinearGradient.diagonal) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 16, weight: .semibold).monospacedDigit())
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Attention alerts widget

    @ViewBuilder
    private func attentionAlertsWidget(_ span: HomeWidgetSpan) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("ATTENTION ALERTS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = alerts.state, !rows.isEmpty {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.danger))
                }
            }
            switch alerts.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.circle", title: "All clear",
                                   subtitle: "No loads need attention right now.")
                } else {
                    let cap = span == .compact ? 1 : 3
                    VStack(spacing: 0) {
                        ForEach(Array(rows.prefix(cap).enumerated()), id: \.element.id) { idx, r in
                            attentionRow(loadId: r.id,
                                         meta: "\(r.loadNumber) · \(r.message)",
                                         title: r.issue.uppercased())
                            if idx < min(rows.count, cap) - 1 {
                                Divider().overlay(palette.borderFaint)
                            }
                        }
                    }
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                }
            case .empty:
                EusoEmptyState(systemImage: "checkmark.circle", title: "All clear",
                               subtitle: "No loads need attention right now.")
            case .error(let e):
                inlineError(e) { Task { await alerts.refresh() } }
            }
        }
    }

    // Reorderable secondary-widget zone is the bespoke ShipperWidgetBoard
    // (below) — it owns the per-widget RESIZE chooser the founder asked for.
}

// MARK: - ShipperWidgetBoard — bespoke resizable + reorderable widget zone
//
// Founder bug 2026-06-02: "there is no resizing the widget capability you
// said you did on homescreen". The shared HomeWidgetGrid already carries a
// span engine, but the shipper catalog rows it reads (owned by another
// file) all declare a single `[.full]` span, so its size picker never
// surfaced on the shipper home. This board re-implements the customize
// surface *locally* so every shipper tile gets a real, working size chooser
// (Compact · Half · Full) — and it persists to the IDENTICAL storage the
// shared grid uses:
//   • UserDefaults cache key `shipper.home.widgetOrder` (array of
//     {widgetId, w, h} — the same CachedSlot shape the grid writes), and
//   • the `users.saveDashboardLayout` / `users.getDashboardLayout` tRPC
//     slots ({widgetId, x, y, w, h}) — the cross-platform 12-col model.
// So a chosen size survives relaunch and round-trips with web.
//
// Reuses the shared, file-internal `HomeWidgetSpan` (from 010_DriverHome):
//   .compact → full width, condensed body (tile reads `\.homeWidgetSpan`)
//   .half    → two tiles share a row (w = 6 on the 12-col model)
//   .full    → one tile per row       (w = 12)

struct ShipperWidgetBoard: View {
    /// A widget slot + the spans the user may resize it to. `.full` is
    /// always the seed when no saved choice exists.
    struct Slot {
        let id: String
        let sizes: [HomeWidgetSpan]
        init(id: String, sizes: [HomeWidgetSpan]) { self.id = id; self.sizes = sizes }
    }

    @Environment(\.palette) private var palette

    let slots: [Slot]
    /// Role string for the save/load endpoint.
    let role: String
    /// Per-user UserDefaults cache key (shared with the cross-platform grid).
    let storageKey: String
    /// (id, resolved span) → tile view. EmptyView when unrecognized (stale
    /// saved layout). The span is passed EXPLICITLY — relying on the
    /// `.environment(\.homeWidgetSpan, …)` injection alone silently fails
    /// when the host screen reads the key on itself rather than inside the
    /// rendered tile (the founder's "Compact does nothing" bug).
    let render: (String, HomeWidgetSpan) -> AnyView

    @State private var order: [String] = []
    @State private var sizes: [String: HomeWidgetSpan] = [:]
    @State private var editing: Bool = false
    @State private var hoverSlot: String? = nil
    @State private var hydrated: Bool = false

    // ── Drag-to-resize (founder ask 2026-06-11: mirror the web grid's
    // corner-drag, translated to touch). State for the in-flight gesture:
    // which tile is being resized, the tier index the drag started at,
    // and the live tier so each snap fires exactly one haptic.
    @State private var resizingSlot: String? = nil
    @State private var resizeBaseIndex: Int = 0
    @State private var resizeLiveIndex: Int = 0

    private var canonicalOrder: [String] { slots.map(\.id) }
    private func slot(for id: String) -> Slot? { slots.first { $0.id == id } }

    /// The spans a widget may resize to (always at least `.full`).
    private func availableSizes(for id: String) -> [HomeWidgetSpan] {
        let s = slot(for: id)?.sizes ?? [.full]
        return s.isEmpty ? [.full] : s
    }

    /// Resolved span — user choice (clamped to availability), else the first
    /// declared span, else `.full`.
    private func span(for id: String) -> HomeWidgetSpan {
        let avail = availableSizes(for: id)
        if let chosen = sizes[id], avail.contains(chosen) { return chosen }
        return avail.first ?? .full
    }

    /// Packs consecutive `.half` tiles two-per-row; everything else is a
    /// full row. Preserves reorder order exactly.
    private var packedRows: [[String]] {
        var rows: [[String]] = []
        var i = 0
        while i < order.count {
            let id = order[i]
            if span(for: id).isHalf, i + 1 < order.count, span(for: order[i + 1]).isHalf {
                rows.append([id, order[i + 1]]); i += 2
            } else {
                rows.append([id]); i += 1
            }
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            ForEach(Array(packedRows.enumerated()), id: \.offset) { _, row in
                if row.count == 2 {
                    HStack(alignment: .top, spacing: 12) {
                        slotView(row[0])
                        slotView(row[1])
                    }
                } else {
                    slotView(row[0])
                }
            }
        }
        .task {
            guard !hydrated else { return }
            hydrated = true
            order = canonicalOrder
            await hydrate()
        }
    }

    // MARK: Toolbar (CUSTOMIZE / DONE + RESET)

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: editing ? "checkmark.circle.fill" : "rectangle.3.group.bubble")
                    .font(.system(size: 11, weight: .heavy))
                Text(editing ? "DONE · resize & reorder" : "CUSTOMIZE WIDGETS")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                Spacer(minLength: 0)
                if editing {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            order = canonicalOrder
                            sizes = [:]
                        }
                    } label: {
                        Text("RESET")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(palette.bgCard, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .foregroundStyle(editing ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                Capsule().strokeBorder(
                    editing ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.18)) {
                    if editing { editing = false; Task { await persist() } }
                    else { editing = true }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: editing)
    }

    // MARK: Per-slot rendering

    @ViewBuilder
    private func slotView(_ id: String) -> some View {
        let activeSpan = span(for: id)
        // Span flows through the render closure (the load-bearing path) AND
        // the environment (for shared components that read the key inside
        // their own body, e.g. catalog tiles reused across role homes).
        let inner = render(id, activeSpan).environment(\.homeWidgetSpan, activeSpan)
        if editing {
            let isHover = hoverSlot == id
            let isResizing = resizingSlot == id
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 10)
                inner
            }
            .overlay(alignment: .topTrailing) { resizeChip(for: id, active: activeSpan) }
            .overlay(alignment: .bottomTrailing) { resizeHandle(for: id, active: activeSpan) }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        (isHover || isResizing) ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: (isHover || isResizing) ? 2 : 1
                    )
                    .animation(.easeOut(duration: 0.12), value: hoverSlot)
                    .animation(.easeOut(duration: 0.12), value: resizingSlot)
            )
            .draggable(id) {
                Text(id)
                    .font(.system(size: 13, weight: .heavy))
                    .padding(10)
                    .background(palette.bgCard, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
            }
            .dropDestination(for: String.self) { droppedIds, _ in
                guard let dropped = droppedIds.first,
                      dropped != id,
                      let fromIdx = order.firstIndex(of: dropped),
                      let toIdx = order.firstIndex(of: id)
                else { return false }
                withAnimation(.easeOut(duration: 0.18)) {
                    let item = order.remove(at: fromIdx)
                    order.insert(item, at: min(toIdx, order.count))
                }
                return true
            } isTargeted: { hovering in
                hoverSlot = hovering ? id : (hoverSlot == id ? nil : hoverSlot)
            }
        } else {
            inner
        }
    }

    /// The explicit size picker shown on every tile in edit mode — tap to
    /// choose Compact / Half / Full from the spans this widget allows.
    /// Writes the same `sizes[id]` the corner drag handle does, so both
    /// affordances persist through the identical layout slot.
    @ViewBuilder
    private func resizeChip(for id: String, active: HomeWidgetSpan) -> some View {
        let avail = availableSizes(for: id)
        Menu {
            Picker("Size", selection: sizeBinding(for: id)) {
                ForEach(avail, id: \.self) { sp in
                    Label(sp.menuLabel, systemImage: sp.menuIcon).tag(sp)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: active.menuIcon)
                    .font(.system(size: 8, weight: .heavy))
                Text(active.menuLabel.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .heavy))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(LinearGradient.diagonal)
            .clipShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel("Resize \(id) widget. Current size \(active.menuLabel).")
    }

    // MARK: Drag-to-resize — the web grid's corner-drag, translated to touch

    /// Size tiers this widget can snap between, ordered smallest → largest
    /// (compact < half < full). The drag handle walks this ladder.
    private func orderedTiers(for id: String) -> [HomeWidgetSpan] {
        let rank: [HomeWidgetSpan: Int] = [.compact: 0, .half: 1, .full: 2]
        return availableSizes(for: id).sorted { (rank[$0] ?? 2) < (rank[$1] ?? 2) }
    }

    /// Points of corner-drag travel per size tier. Tuned so a thumb swipe
    /// across roughly a quarter of the screen crosses one tier.
    private static let resizeStepPoints: CGFloat = 84

    /// Corner drag handle — trailing-bottom grabber shown on every
    /// resizable tile in edit mode. Dragging outward (down/right) grows
    /// the widget a tier; inward (up/left) shrinks it. Each snap lands
    /// with a haptic tick + spring re-layout, mirroring the web
    /// platform's corner-drag resize semantics on touch. Tiles with a
    /// single declared span render no handle (nothing to resize).
    @ViewBuilder
    private func resizeHandle(for id: String, active: HomeWidgetSpan) -> some View {
        let tiers = orderedTiers(for: id)
        if tiers.count > 1 {
            let isResizing = resizingSlot == id
            ZStack {
                // Corner rails — two concentric quarter-arcs reading as a
                // "grab corner" affordance (bespoke, not a stock glyph).
                CornerGrabberShape()
                    .stroke(
                        isResizing ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 14, height: 14)
            }
            .frame(width: 36, height: 36, alignment: .bottomTrailing)
            .padding(.trailing, 8)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if resizingSlot != id {
                            // Gesture start — anchor on the current tier.
                            resizingSlot = id
                            let idx = tiers.firstIndex(of: span(for: id)) ?? (tiers.count - 1)
                            resizeBaseIndex = idx
                            resizeLiveIndex = idx
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        // Outward (down/right) grows, inward shrinks —
                        // average the two axes so a pure-diagonal pull
                        // tracks 1:1 with the finger.
                        let travel = (value.translation.width + value.translation.height) / 2
                        let steps = Int((travel / Self.resizeStepPoints).rounded())
                        let target = max(0, min(tiers.count - 1, resizeBaseIndex + steps))
                        if target != resizeLiveIndex {
                            resizeLiveIndex = target
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                sizes[id] = tiers[target]
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        resizingSlot = nil
                        cacheLocally()
                        Task { await persist() }
                    }
            )
            .overlay(alignment: .topTrailing) {
                // Live tier readout while dragging — floats above the
                // handle so the thumb never covers it.
                if isResizing {
                    Text(span(for: id).menuLabel.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(LinearGradient.diagonal, in: Capsule())
                        .offset(x: -2, y: -26)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Resize \(id) widget by dragging. Current size \(active.menuLabel).")
        }
    }

    /// Two-way binding for a widget's span — animates the repack and
    /// persists immediately so the size survives even if the user leaves
    /// without tapping DONE.
    private func sizeBinding(for id: String) -> Binding<HomeWidgetSpan> {
        Binding(
            get: { span(for: id) },
            set: { newSpan in
                withAnimation(.easeOut(duration: 0.2)) { sizes[id] = newSpan }
                cacheLocally()
                Task { await persist() }
            }
        )
    }

    // MARK: Persistence (shared shape with the cross-platform grid)

    private struct CachedSlot: Codable { let widgetId: String; let w: Int; let h: Int }

    private func hydrate() async {
        // Local cache first (new {widgetId,w,h} format, legacy [String] order).
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            if let cached = try? JSONDecoder().decode([CachedSlot].self, from: data), !cached.isEmpty {
                applySlots(cached.map { ($0.widgetId, $0.w, $0.h) })
            } else if let legacy = try? JSONDecoder().decode([String].self, from: data), !legacy.isEmpty {
                order = reconcile(legacy)
            }
        }
        struct In: Encodable { let role: String }
        struct ServerSlot: Decodable { let widgetId: String; let w: Int?; let h: Int? }
        struct Out: Decodable { let layout: [ServerSlot]?; let updatedAt: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("users.getDashboardLayout", input: In(role: role))
            if let server = r.layout, !server.isEmpty {
                let resolved = server.map { ($0.widgetId, $0.w ?? 12, $0.h ?? 8) }
                await MainActor.run { applySlots(resolved) }
                cacheLocally()
            }
        } catch { /* offline / unauth — local cache or canonical default holds */ }
    }

    /// Maps saved (id + w/h) slots back into `order` + `sizes`, clamping each
    /// w/h to a span this widget actually offers.
    private func applySlots(_ slots: [(id: String, w: Int, h: Int)]) {
        order = reconcile(slots.map { $0.id })
        var resolved: [String: HomeWidgetSpan] = [:]
        for s in slots where order.contains(s.id) {
            let candidate = HomeWidgetSpan.from(w: s.w, h: s.h)
            let avail = availableSizes(for: s.id)
            resolved[s.id] = avail.contains(candidate) ? candidate : (avail.first ?? .full)
        }
        sizes = resolved
    }

    private func cacheLocally() {
        let rows = order.map { id -> CachedSlot in
            let g = span(for: id).grid
            return CachedSlot(widgetId: id, w: g.w, h: g.h)
        }
        if let data = try? JSONEncoder().encode(rows) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func persist() async {
        cacheLocally()
        struct Slot: Encodable { let widgetId: String; let x: Int; let y: Int; let w: Int; let h: Int }
        struct In: Encodable { let role: String; let layout: [Slot] }
        struct Out: Decodable { let success: Bool? }
        var payload: [Slot] = []
        var cursorX = 0, rowY = 0
        for id in order {
            let g = span(for: id).grid
            if cursorX + g.w > 12 { cursorX = 0; rowY += 1 }
            payload.append(Slot(widgetId: id, x: cursorX, y: rowY, w: g.w, h: g.h))
            cursorX += g.w
            if cursorX >= 12 { cursorX = 0; rowY += 1 }
        }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "users.saveDashboardLayout",
                input: In(role: role, layout: payload)
            )
        } catch { /* server unreachable — local cache holds */ }
    }

    /// Preserves saved order, drops unknown ids, appends newly-shipped slots.
    private func reconcile(_ saved: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in saved where !seen.contains(s) && canonicalOrder.contains(s) {
            out.append(s); seen.insert(s)
        }
        for s in canonicalOrder where !seen.contains(s) { out.append(s) }
        return out
    }
}

// MARK: - CornerGrabberShape — bespoke resize-corner affordance
//
// Two nested L-strokes hugging the bottom-trailing corner — the touch
// translation of the web grid's corner-drag chevron. Drawn as a Shape so
// it strokes crisply at any scale and inherits whatever style (gradient
// while resizing, tertiary at rest) the handle applies.

struct CornerGrabberShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Outer L — full corner.
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Inner L — inset echo.
        let inset: CGFloat = rect.width * 0.45
        p.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset * 0.1))
        p.addLine(to: CGPoint(x: rect.maxX - inset * 0.1, y: rect.maxY - inset * 0.1))
        p.addLine(to: CGPoint(x: rect.maxX - inset * 0.1, y: rect.minY + inset))
        return p
    }
}

// MARK: - Notification names (canonical CTA hooks for the Shipper Home)

extension Notification.Name {
    /// Fired by the "Post a load" CTA on 200 Shipper Home. Routes to
    /// 204 Post a Load via the parent app's deep-link router.
    static let eusoShipperLoadCreate    = Notification.Name("eusoShipperLoadCreate")
    /// Fired by "Browse carriers" → 213 Catalyst Scorecard.
    static let eusoShipperBrowseCarriers = Notification.Name("eusoShipperBrowseCarriers")
    /// Fired by tapping an active-load row → 205 Load Detail.
    static let eusoShipperLoadOpen      = Notification.Name("eusoShipperLoadOpen")
    /// Fired by "See all (N)" → 201 Shipper Loads.
    static let eusoShipperLoadListOpen  = Notification.Name("eusoShipperLoadListOpen")
    /// Fired by tapping the eSang strip → eSang sheet over Home.
    static let eusoShippereSangOpen     = Notification.Name("eusoShippereSangOpen")
}

// MARK: - Screen wrapper

struct ShipperHomeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            ShipperHome()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_200(),
                trailing: shipperNavTrailing_200(),
                orbState: .idle
            )
        }
    }
}

// Shipper bottom-nav doctrine (2026-04-28): Home / Create Load / ESANG /
// Loads / Me. Wallet, settlements, payments, reports, contacts, analytics
// all live under the Me sub-section, NOT promoted to the chrome.
// Per parity mandate §1: NAV is out of scope.
private func shipperNavLeading_200() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house.fill",                    isCurrent: true),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",   isCurrent: false)]
}

private func shipperNavTrailing_200() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: false)]
}

// MARK: - Previews

#Preview("200 · Shipper · Home · Night") {
    ShipperHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("200 · Shipper · Home · Afternoon") {
    ShipperHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
