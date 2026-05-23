//
//  500_CatalystHome.swift
//  EusoTrip — Catalyst · Home (brick 500).
//
//  First brick on the Catalyst role track (500s). Replaces the
//  `RolePlaceholderScreen` stub the dev chrome was rendering for
//  `ProductionScreen.Role.catalyst`. Direct mirror of
//  `Views/Broker/400_BrokerHome.swift` shipped in the 99th firing
//  (which itself mirrored `Views/Carrier/300_CarrierHome.swift` and
//  `Views/Shipper/200_ShipperHome.swift`).
//
//  Catalyst is the AI-augmented dispatch / SpectraMatch operator
//  surface — the role that runs the autonomous load-matching agents
//  per the EusoTrip backend §16 intelligence slice (Autopilot 7-layer
//  cortex, 52 agents, SpectraMatch crude-oil 12-param fit). The home
//  re-frames the four-card hierarchy around match flow + fit-score
//  rather than tender flow or active-load count.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  accent — no `.fill(Brand.blue)` / `.tint(Brand.blue)`), §2 (no
//  Toggles on this brick), §4 (tokenized spacing / radius / type),
//  §5 (palette semantic only, no hard-coded `Color.white` /
//  `Color.black` / `Color.gray` fills), §3 (`AnyShapeStyle` wrapping
//  for ternary shape-styles), §10 (previews compile in isolation).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data, plugged
//  into backend"):
//
//    • KPI strip → `catalysts.getDashboardStats` via
//      `CatalystHomeDashboardStore` (LiveDataStores.swift). Server
//      returns a six-figure envelope: activeMatches, matchedThisWeek,
//      deliveredThisWeek, avgFitScore, onTimeRate, gmvThisWeek.
//      Backend convention mirrors `brokers.getDashboardStats`.
//    • "Needs your attention" alert strip →
//      `catalysts.getLoadsRequiringAttention` via
//      `CatalystAlertsStore`. Empty until the catalyst exception
//      engine flags a match-stall, fit-drift, autopilot-fault,
//      capacity-shortage, or rate-misfit.
//    • "Active matches" feed → `catalysts.getActiveMatches` via
//      `CatalystActiveMatchesStore`.
//    • "Recent activity" feed → `catalysts.getRecentMatches` via
//      `CatalystRecentMatchesStore`.
//    • Zero synthesised data. Each card switches over its store's
//      RemoteState; `.loading` shows a skeleton, `.empty` renders
//      `EusoEmptyState`, `.error` renders an inline retry, and
//      `.loaded` paints the real values. If the backend has not
//      yet exposed `catalysts.*`, every card resolves to `.error`
//      and offers retry — no placeholder data is ever shown,
//      satisfying doctrine §11 + `MockDataGuard`.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct CatalystHome: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var dashboard = CatalystHomeDashboardStore()
    @StateObject private var alerts    = CatalystAlertsStore()
    @StateObject private var matches   = CatalystActiveMatchesStore()
    @StateObject private var recent    = CatalystRecentMatchesStore()

    // 134th firing — when the user taps the "View all" CTA on the
    // active-matches card header, present 501_CatalystMatches as a
    // sheet so the home → board transition is a real working flow,
    // not a dead button. Tracks a Bool rather than an item identity
    // because the sheet is the same regardless of which row was
    // tapped (the full match-board, filtered server-side later).
    @State private var presentingMatchesBoard: Bool = false
    @State private var selectedMatch: CatalystAPI.ActiveMatch? = nil
    @State private var selectedRecent: CatalystAPI.RecentMatch? = nil
    @State private var presentingAlert: CatalystAPI.LoadAlert? = nil

    // Founder ask 2026-05-07: weather widget pinned to top of
    // every role's home; attention strip collapsible.
    @State private var weather: WeatherSnapshot? = nil
    @State private var weatherNeedsLocation: Bool = false
    @State private var attentionExpanded: Bool = (UserDefaults.standard.object(forKey: "catalyst.home.attentionExpanded") as? Bool) ?? true

    // ── Home-widget customization — uses shared HomeWidgetGrid. ──
    private let widgetLayoutKey = "catalyst.home.widgetOrder"
    private let catalystCanonicalOrder: [String] = ["activeMatches", "gmv_summary", "catalyst_alerts", "recent", "news"]

    private func catalystHomeRender(_ id: String) -> AnyView {
        switch id {
        case "activeMatches":   AnyView(activeMatchesCard)
        case "gmv_summary":     AnyView(gmvSummaryWidget)
        case "catalyst_alerts": AnyView(catalystAlertsWidget)
        case "recent":          AnyView(recentActivityCard)
        case "news":            AnyView(NewsCarouselWidget())
        default:                AnyView(EmptyView())
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                weatherSection         // pinned top per founder doctrine
                // Catalyst Spark Brief — Tier 1 #24 ship 2026-05-21.
                // Settlement reconciliation + factoring decisions +
                // carrier scorecards, overnight via SubagentOrchestrator.
                SparkBriefCard(role: .catalyst)
                kpiStrip
                collapsibleAttentionStrip
                HomeWidgetGrid(
                    canonicalOrder: catalystCanonicalOrder,
                    role: "CATALYST",
                    storageKey: widgetLayoutKey,
                    render: { id in catalystHomeRender(id) }
                )
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .sheet(isPresented: $presentingMatchesBoard) {
            CatalystMatchesScreen(theme: palette)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Active match row tap → open 502 Match Detail with the
        // matchId pre-bound. RealtimeService load events refresh both
        // surfaces while the sheet is open.
        .sheet(item: $selectedMatch) { match in
            CatalystMatchDetailScreen(
                theme: palette,
                matchId: match.id,
                previewLoadNumber: match.loadNumber,
                previewLane: "\(match.origin) → \(match.destination)",
                previewStartedAt: nil,
                previewCandidateCount: match.candidateCount,
                previewBestFitScore: match.bestFitScore,
                previewAgentName: match.agentName.isEmpty ? nil : match.agentName
            )
            .environmentObject(session)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // Recent activity row tap → open 305 Catalyst Load Detail for
        // the resolved match's loadId. Same canvas the dispatcher uses
        // when opening the load from the dispatch board.
        .sheet(item: $selectedRecent) { recent in
            CatalystLoadDetailScreen(theme: palette, loadId: recent.id)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Alert row tap → 305 Load Detail focused on the load that
        // triggered the alert (match-stall, fit-drift, capacity-shortage,
        // etc). The catalyst can then update status / reassign / message
        // eSang directly from the load surface.
        .sheet(item: $presentingAlert) { alert in
            CatalystLoadDetailScreen(theme: palette, loadId: alert.id)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // RealtimeService → load events refresh the home surface live.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await refreshAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await refreshAll() }
        }
        .screenTileRoot()
    }

    private func refreshAll() async {
        async let a: Void = dashboard.refresh()
        async let b: Void = alerts.refresh()
        async let c: Void = matches.refresh()
        async let d: Void = recent.refresh()
        async let w: WeatherSnapshot? = WeatherService.shared.fetchCurrent()
        let snap = await w
        _ = await (a, b, c, d)
        weather = snap
        let status = WeatherService.shared.authorizationStatus
        weatherNeedsLocation = (snap == nil) && (
            status == .notDetermined ||
            status == .denied ||
            status == .restricted
        )
    }

    /// Live weather card — same WeatherCard component used by Driver
    /// 010 + Shipper 200. Empty when WeatherKit hasn't returned yet
    /// AND CoreLocation is authorized (transient state); shows the
    /// "Enable location" CTA when authorization is missing.
    @ViewBuilder
    private var weatherSection: some View {
        if let w = weather {
            WeatherCard(snapshot: w)
        } else if weatherNeedsLocation {
            catalystEnableLocationCard
        }
    }

    private var catalystEnableLocationCard: some View {
        Button {
            let status = WeatherService.shared.authorizationStatus
            if status == .notDetermined {
                WeatherService.shared.requestPermissionIfNeeded()
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(LinearGradient.diagonal))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable location for live weather")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Powers the dispatch decisions ESANG surfaces in your morning brief.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Wraps the existing `attentionStrip` in a graceful collapsible
    /// chrome. Header always visible; body slides + fades on toggle.
    @ViewBuilder
    private var collapsibleAttentionStrip: some View {
        if case .loaded(let rows) = alerts.state, !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        attentionExpanded.toggle()
                    }
                    UserDefaults.standard.set(attentionExpanded, forKey: "catalyst.home.attentionExpanded")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("NEEDS YOUR ATTENTION")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textPrimary)
                        Text("\(rows.count)")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(LinearGradient.diagonal))
                        Spacer(minLength: 0)
                        Image(systemName: attentionExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if attentionExpanded {
                    attentionStrip
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                }
            }
        } else {
            attentionStrip
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("CATALYST · HOME")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(headline)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text(subhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// Identity-aware headline. Falls back to the role label so the
    /// header never reads as a placeholder.
    private var headline: String {
        if let name = session.user?.firstName, !name.isEmpty {
            return "On the wire, \(name)"
        }
        return "Catalyst · Home"
    }

    private var subhead: String {
        if let outer = dashboard.state.value, let s = outer {
            let live = s.activeMatches
            let week = s.matchedThisWeek
            return "\(live) live match\(live == 1 ? "" : "es") · \(week) matched · 7d"
        }
        return "Loading match fabric…"
    }

    // MARK: - KPI strip

    @ViewBuilder
    private var kpiStrip: some View {
        switch dashboard.state {
        case .loading:
            kpiSkeleton
        case .loaded(let maybe):
            if let s = maybe {
                kpiGrid(s)
            } else {
                EusoEmptyState(
                    systemImage: "chart.bar",
                    title: "No KPIs yet",
                    subtitle: "Once SpectraMatch surfaces its first match, the dashboard will populate the moment a carrier accepts."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "chart.bar",
                title: "No KPIs yet",
                subtitle: "Once SpectraMatch surfaces its first match, the dashboard will populate the moment a carrier accepts."
            )
        case .error(let e):
            inlineError(e) { Task { await dashboard.refresh() } }
        }
    }

    private var kpiSkeleton: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private func kpiGrid(_ s: CatalystAPI.DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            // Every KPI tile drills into the live matches board — that's
            // the canvas where the catalyst can filter by status, see
            // each match, and act on it. GMV currently routes there too
            // until a dedicated Catalyst settlement surface ships.
            Button { presentingMatchesBoard = true } label: {
                kpiTile(label: "ACTIVE MATCHES", value: "\(s.activeMatches)",       sub: "agents wired")
            }
            .buttonStyle(.plain)
            Button { presentingMatchesBoard = true } label: {
                kpiTile(label: "MATCHED · 7D",   value: "\(s.matchedThisWeek)",     sub: "carrier accepted")
            }
            .buttonStyle(.plain)
            Button { presentingMatchesBoard = true } label: {
                kpiTile(label: "DELIVERED · 7D", value: "\(s.deliveredThisWeek)",   sub: "completed this week")
            }
            .buttonStyle(.plain)
            Button { presentingMatchesBoard = true } label: {
                kpiTile(label: "GMV · 7D",       value: dollars(s.gmvThisWeek),     sub: "lane value · 7d")
            }
            .buttonStyle(.plain)
        }
    }

    private func kpiTile(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            Text(sub)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    /// Format a SpectraMatch fit score (0.0…1.0) as a percentage
    /// rounded to whole digits. Returns "—" for zero so the empty
    /// case never renders as "0%".
    private func fitScore(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        return "\(Int((v * 100).rounded()))%"
    }

    // MARK: - Attention strip

    @ViewBuilder
    private var attentionStrip: some View {
        switch alerts.state {
        case .loading:
            EmptyView()
        case .empty:
            // Don't render anything — silence is the right empty state
            // for an alert feed (empty == nothing's wrong).
            EmptyView()
        case .loaded(let rows):
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("NEEDS YOUR ATTENTION")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                ForEach(rows) { row in
                    Button {
                        presentingAlert = row
                    } label: {
                        alertRow(row)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .error(let e):
            inlineError(e) { Task { await alerts.refresh() } }
        }
    }

    private func alertRow(_ row: CatalystAPI.LoadAlert) -> some View {
        let severityColor: Color = {
            switch row.severity.lowercased() {
            case "critical":  return Brand.danger
            case "warning":   return Brand.warning
            default:          return palette.textTertiary
            }
        }()
        return HStack(spacing: Space.s3) {
            Circle()
                .fill(AnyShapeStyle(severityColor))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(row.message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(row.issue.uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(severityColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(severityColor.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Active matches

    @ViewBuilder
    private var activeMatchesCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ACTIVE MATCHES")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = matches.state {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                // 134th firing — gradient "View all" CTA presents the
                // full 501_CatalystMatches board as a sheet. Only
                // surfaces once the home strip has loaded rows so the
                // CTA never lies about there being a board behind it.
                if case .loaded(let rows) = matches.state, !rows.isEmpty {
                    Button {
                        presentingMatchesBoard = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("VIEW ALL")
                                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .heavy))
                        }
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(
                            Capsule().strokeBorder(
                                LinearGradient.diagonal.opacity(0.5),
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            switch matches.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        Button {
                            selectedMatch = row
                        } label: {
                            matchRow(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "scope",
                    title: "No live matches",
                    subtitle: "Start an autopilot agent and you'll see its match candidates ladder up here in real time."
                )
            case .error(let e):
                inlineError(e) { Task { await matches.refresh() } }
            }
        }
    }

    private func matchRow(_ row: CatalystAPI.ActiveMatch) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("\(row.origin) → \(row.destination)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text("\(row.candidateCount) candidate\(row.candidateCount == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Text("started \(row.startedAt)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                if !row.agentName.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text(row.agentName)
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("LIVE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1))
                if row.bestFitScore > 0 {
                    Text(fitScore(row.bestFitScore))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("best fit")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Recent activity

    @ViewBuilder
    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RECENT ACTIVITY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch recent.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        Button {
                            selectedRecent = row
                        } label: {
                            recentRow(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "clock",
                    title: "No recent activity",
                    subtitle: "Once a match resolves or a load delivers, it'll show up here with the lane and final fit score."
                )
            case .error(let e):
                inlineError(e) { Task { await recent.refresh() } }
            }
        }
    }

    private func recentRow(_ row: CatalystAPI.RecentMatch) -> some View {
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
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                if row.finalFitScore > 0 {
                    Text(fitScore(row.finalFitScore))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
                if !row.resolvedAt.isEmpty {
                    Text(row.resolvedAt)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Shared widgets

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    // MARK: - Catalyst alerts widget

    @ViewBuilder
    private var catalystAlertsWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("CATALYST ALERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
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
                                   subtitle: "No matches need attention right now.")
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(rows.prefix(3)) { alertRow($0) }
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "checkmark.circle", title: "All clear",
                               subtitle: "No matches need attention right now.")
            case .error(let e):
                inlineError(e) { Task { await alerts.refresh() } }
            }
        }
    }

    // MARK: - GMV summary widget

    @ViewBuilder
    private var gmvSummaryWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("GMV SUMMARY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch dashboard.state {
            case .loading:
                listSkeleton
            case .loaded(let maybe):
                if let s = maybe { gmvTiles(s) }
            case .empty:
                EusoEmptyState(systemImage: "chart.bar", title: "No GMV data",
                               subtitle: "Run a match agent and this week's GMV will appear here.")
            case .error(let e):
                inlineError(e) { Task { await dashboard.refresh() } }
            }
        }
    }

    private func gmvTiles(_ s: CatalystAPI.DashboardStats) -> some View {
        HStack(spacing: Space.s2) {
            kpiTile(label: "GMV · 7D",    value: dollars(s.gmvThisWeek),   sub: "gross move value")
            kpiTile(label: "AVG FIT",     value: String(format: "%.0f%%", s.avgFitScore * 100), sub: "SpectraMatch score")
            kpiTile(label: "MATCHED · 7D", value: "\(s.matchedThisWeek)", sub: "loads matched")
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
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

}

// MARK: - Screen wrapper

struct CatalystHomeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            CatalystHome()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_500(),
                trailing: catalystNavTrailing_500(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_500() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house.fill",   isCurrent: true),
     NavSlot(label: "Matches", systemImage: "scope", isCurrent: false)]
}

private func catalystNavTrailing_500() -> [NavSlot] {
    [NavSlot(label: "Network", systemImage: "person.2",   isCurrent: false),
     NavSlot(label: "Me",      systemImage: "person",     isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// This is a doctrine §10 requirement (previews compile and render
// in isolation, no live API).

#Preview("500 · Catalyst · Home · Night") {
    CatalystHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("500 · Catalyst · Home · Afternoon") {
    CatalystHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
