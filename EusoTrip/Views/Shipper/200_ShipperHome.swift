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

    /// The signed-in user's avatar photo (users.profilePicture, stored as a
    /// base64 data URL by profile.updateAvatar). Fetched on appear + on
    /// .eusoProfileUpdated; duAvatar renders it, falling back to initials.
    @State private var avatarImage: UIImage? = nil

    // ── Home-widget customization ─────────────────────────────────────
    // The shared grid is the cross-role layout authority. It owns resize,
    // reorder, remove/re-add, reset, server sync, and the offline cache while
    // this screen supplies Shipper-specific content for each slot.
    private let widgetLayoutKey = "shipper.home.widgetOrder"

    private let shipperHomeCanonicalOrder: [String] = [
        "weather", "shipper_actions", "shipper_summary", "activeLoads",
        "esang", "spend_summary", "attention_alerts", "recent", "news",
    ]

    /// Per-tile renderer. The shared grid passes the resolved span explicitly,
    /// so every size tier re-lays out the role-owned content without relying
    /// on an environment value read above the widget boundary.
    private func shipperHomeRender(_ id: String, _ span: HomeWidgetSpan) -> AnyView {
        switch id {
        case "weather":           AnyView(weatherSection)
        case "shipper_actions":   AnyView(shipperActionsWidget(span))
        case "shipper_summary":   AnyView(statRow)
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
                // First-load unlock cascade: each top-level section springs
                // into place top-to-bottom (scale 0.92 + blur 5pt + 50 ms
                // stagger) once per cold launch; settled on re-visit.
                StaggeredEntranceStack(alignment: .leading, spacing: Space.s5) {
                    HomeWidgetGrid(
                        canonicalOrder: shipperHomeCanonicalOrder,
                        role: "SHIPPER",
                        storageKey: widgetLayoutKey,
                        weather: { AnyView(weatherSection) },
                        renderWithSpan: { id, span in shipperHomeRender(id, span) }
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
        _ = await (a, b, c, d, p, ag, av)
        unread.refresh()  // EUSO-2057: kicks UnreadMessageStore -> messaging.getUnreadCount
    }

    /// Auth-scoped live weather. The shared widget owns its provider request,
    /// cache, permission state, and retry cadence for every role home.
    @ViewBuilder
    private var weatherSection: some View {
        // Always-visible bespoke weather surface — owns its own fetch and
        // renders an honest state (data / loading / enable-location /
        // unavailable) so the widget never disappears on any role.
        HomeWeatherWidget()
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

    // MARK: - Shipper actions widget

    /// The two primary shipper commands stay on Home, but now participate in
    /// the same move/resize/remove contract as every other role module.
    @ViewBuilder
    private func shipperActionsWidget(_ span: HomeWidgetSpan) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER ACTIONS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            if span == .half {
                VStack(spacing: Space.s2) {
                    postLoadAction
                    browseCarriersAction
                }
            } else {
                HStack(spacing: Space.s2) {
                    postLoadAction
                    browseCarriersAction
                }
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.lg)
    }

    private var postLoadAction: some View {
        CTAButton(title: "Post a load") {
            NotificationCenter.default.post(name: .eusoShipperLoadCreate, object: nil)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Post a load, primary action")
    }

    private var browseCarriersAction: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperBrowseCarriers, object: nil)
        } label: {
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
                Text(error.eusoUserCopy)
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

}

// HomeWidgetGrid is the only Shipper layout authority. The retired local
// board duplicated persistence and resize behavior and is intentionally gone.
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
