//
//  400_BrokerHome.swift
//  EusoTrip — Broker · Home (brick 400).
//
//  First brick on the Broker role track (400s). Replaces the
//  `RolePlaceholderScreen` stub the dev chrome was rendering for
//  `ProductionScreen.Role.broker`. Direct mirror of
//  `Views/Carrier/300_CarrierHome.swift` shipped in the 100th firing
//  (which itself mirrored `Views/Shipper/200_ShipperHome.swift`).
//  Swung to the broker-side of every wire — the broker sits between
//  the shipper (origin of freight) and the carrier (mover of freight),
//  so the home re-frames the four-card hierarchy around margin and
//  tender flow rather than active-load count.
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
//    • KPI strip → `brokers.getDashboardStats` via
//      `BrokerHomeDashboardStore` (LiveDataStores.swift). Server
//      returns a six-figure envelope: openTenders, awardedThisWeek,
//      deliveredThisWeek, marginPerLoad, onTimeRate,
//      grossMarginThisWeek. Backend convention mirrors
//      `carriers.getDashboardStats`.
//    • "Needs your attention" alert strip →
//      `brokers.getLoadsRequiringAttention` via
//      `BrokerAlertsStore`. Empty until the broker exception engine
//      flags carrier no-show, customer escalation, late tender,
//      detention dispute, or rate-confirmation reject.
//    • "Open tenders" feed → `brokers.getOpenTenders` via
//      `BrokerOpenTendersStore`.
//    • "Recent activity" feed → `brokers.getRecentLoads` via
//      `BrokerRecentLoadsStore`.
//    • Zero synthesised data. Each card switches over its store's
//      RemoteState; `.loading` shows a skeleton, `.empty` renders
//      `EusoEmptyState`, `.error` renders an inline retry, and
//      `.loaded` paints the real values. If the backend has not
//      yet exposed `brokers.*`, every card resolves to `.error`
//      and offers retry — no placeholder data is ever shown,
//      satisfying doctrine §11 + `MockDataGuard`.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct BrokerHome: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var dashboard = BrokerHomeDashboardStore()
    @StateObject private var alerts    = BrokerAlertsStore()
    @StateObject private var tenders   = BrokerOpenTendersStore()
    @StateObject private var recent    = BrokerRecentLoadsStore()
    /// Tier 2 #37 (2026-05-21) — present the conversational lane
    /// intelligence sheet. Surfaces rate band + drivers + surcharges
    /// + a one-paragraph broker advisory for any lane question.
    @State private var showLaneIntel: Bool = false

    // ── Home-widget customization — uses shared HomeWidgetGrid. ──
    private let widgetLayoutKey = "broker.home.widgetOrder"
    private let brokerCanonicalOrder: [String] = ["openTenders", "margin_summary", "broker_alerts", "recent", "news"]

    private func brokerHomeRender(_ id: String) -> AnyView {
        switch id {
        case "openTenders":    AnyView(openTendersCard)
        case "margin_summary": AnyView(marginSummaryWidget)
        case "broker_alerts":  AnyView(brokerAlertsWidget)
        case "recent":         AnyView(recentActivityCard)
        case "news":           AnyView(NewsCarouselWidget())
        default:               AnyView(EmptyView())
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                attentionStrip
                laneIntelCTA
                catalystVettingCTA
                HomeWidgetGrid(
                    canonicalOrder: brokerCanonicalOrder,
                    role: "BROKER",
                    storageKey: widgetLayoutKey,
                    render: { id in brokerHomeRender(id) }
                )
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .screenTileRoot()
        .sheet(isPresented: $showLaneIntel) {
            LaneIntelSheet(companyId: Int(session.user?.companyId ?? "") ?? 1)
        }
    }

    /// 2026-05-21 — eusotrip-killers screen-porting sweep. Routes
    /// to 406 Catalyst Vetting (port of web `CatalystVetting.tsx`).
    /// Backed by `brokers.{getPendingVetting, getVettingStats,
    /// approveCatalyst, rejectCatalyst}` — all real DB writes, no
    /// stubs.
    private var catalystVettingCTA: some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoBrokerNavSwap,
                object: nil,
                userInfo: ["screenId": "406"]
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.2.crop.square.stack.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review catalyst applications")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Approve or reject pending onboarding requests.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 12)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Tier 2 #37 — entry CTA into the conversational lane-intel
    /// sheet. Sits between the attention strip and the open-tenders
    /// card so brokers reach for it while triaging which tenders
    /// to bid on.
    private var laneIntelCTA: some View {
        Button {
            showLaneIntel = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask ESANG about a lane")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Rate band + drivers + surcharges from your last 90 days.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, 12)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func refreshAll() async {
        async let a: Void = dashboard.refresh()
        async let b: Void = alerts.refresh()
        async let c: Void = tenders.refresh()
        async let d: Void = recent.refresh()
        _ = await (a, b, c, d)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "briefcase.fill")
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
                    Text("BROKER · HOME")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(headline)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
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
            return "Good shift, \(name)"
        }
        return "Broker · Home"
    }

    private var subhead: String {
        if let outer = dashboard.state.value, let s = outer {
            let tenders = s.openTenders
            let awarded = s.awardedThisWeek
            return "\(tenders) open tender\(tenders == 1 ? "" : "s") · \(awarded) awarded · 7d"
        }
        return "Loading brokerage fabric…"
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
                    subtitle: "Tender your first load and the dashboard will populate the moment a carrier accepts."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "chart.bar",
                title: "No KPIs yet",
                subtitle: "Tender your first load and the dashboard will populate the moment a carrier accepts."
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

    private func kpiGrid(_ s: BrokerAPI.DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            kpiTile(label: "OPEN TENDERS",   value: "\(s.openTenders)",        sub: "awaiting carrier")
            kpiTile(label: "AWARDED · 7D",   value: "\(s.awardedThisWeek)",    sub: "carrier accepted")
            kpiTile(label: "DELIVERED · 7D", value: "\(s.deliveredThisWeek)",  sub: "completed this week")
            kpiTile(label: "MARGIN · 7D",    value: dollars(s.grossMarginThisWeek), sub: "gross margin · 7d")
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
                    alertRow(row)
                }
            }
        case .error(let e):
            inlineError(e) { Task { await alerts.refresh() } }
        }
    }

    private func alertRow(_ row: BrokerAPI.LoadAlert) -> some View {
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

    // MARK: - Open tenders

    @ViewBuilder
    private var openTendersCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.gearshape.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("OPEN TENDERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = tenders.state {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            switch tenders.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { tenderRow($0) }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "doc.badge.gearshape",
                    title: "No open tenders",
                    subtitle: "Post a load and you'll see it move here while carriers respond."
                )
            case .error(let e):
                inlineError(e) { Task { await tenders.refresh() } }
            }
        }
    }

    private func tenderRow(_ row: BrokerAPI.OpenTender) -> some View {
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
                    Text("\(row.respondingCarriers) carrier\(row.respondingCarriers == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Text("posted \(row.postedAt)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                if !row.shipper.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text(row.shipper)
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("OPEN")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1))
                if row.targetRate > 0 {
                    Text(dollars(row.targetRate))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
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
                    ForEach(rows) { recentRow($0) }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "clock",
                    title: "No recent activity",
                    subtitle: "Once a tender is awarded or a load delivers, it'll show up here with the lane and net margin."
                )
            case .error(let e):
                inlineError(e) { Task { await recent.refresh() } }
            }
        }
    }

    private func recentRow(_ row: BrokerAPI.RecentLoad) -> some View {
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
                if row.netMargin > 0 {
                    Text(dollars(row.netMargin))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
                if !row.deliveredAt.isEmpty {
                    Text(row.deliveredAt)
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

    // MARK: - Broker alerts widget

    @ViewBuilder
    private var brokerAlertsWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("BROKER ALERTS")
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
                                   subtitle: "No loads need attention right now.")
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(rows.prefix(3)) { alertRow($0) }
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "checkmark.circle", title: "All clear",
                               subtitle: "No loads need attention right now.")
            case .error(let e):
                inlineError(e) { Task { await alerts.refresh() } }
            }
        }
    }

    // MARK: - Margin summary widget

    @ViewBuilder
    private var marginSummaryWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("MARGIN SUMMARY")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch dashboard.state {
            case .loading:
                listSkeleton
            case .loaded(let maybe):
                if let s = maybe { marginTiles(s) }
            case .empty:
                EusoEmptyState(systemImage: "chart.line.uptrend.xyaxis", title: "No margin data",
                               subtitle: "Deliver a load and this week's margin will appear here.")
            case .error(let e):
                inlineError(e) { Task { await dashboard.refresh() } }
            }
        }
    }

    private func marginTiles(_ s: BrokerAPI.DashboardStats) -> some View {
        HStack(spacing: Space.s2) {
            kpiTile(label: "MARGIN · 7D",  value: dollars(s.grossMarginThisWeek), sub: "gross this week")
            kpiTile(label: "PER LOAD",     value: dollars(s.marginPerLoad),        sub: "avg margin")
            kpiTile(label: "ON-TIME",      value: String(format: "%.1f%%", s.onTimeRate * 100), sub: "delivery rate")
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

struct BrokerHomeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            BrokerHome()
        } nav: {
            BottomNav(
                leading: brokerNavLeading_400(),
                trailing: brokerNavTrailing_400(),
                orbState: .idle
            )
        }
    }
}

private func brokerNavLeading_400() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house.fill",   isCurrent: true),
     NavSlot(label: "Tenders", systemImage: "doc.badge.gearshape", isCurrent: false)]
}

private func brokerNavTrailing_400() -> [NavSlot] {
    [NavSlot(label: "Carriers", systemImage: "person.2",   isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person",     isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// This is a doctrine §10 requirement (previews compile and render
// in isolation, no live API).

#Preview("400 · Broker · Home · Night") {
    BrokerHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("400 · Broker · Home · Afternoon") {
    BrokerHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
