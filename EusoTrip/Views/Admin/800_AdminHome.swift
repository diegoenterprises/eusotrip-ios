//
//  800_AdminHome.swift
//  EusoTrip — Admin · Home (brick 800).
//
//  First brick on the Admin role track (800s) — and the brick that
//  closes the role-anchor sweep so all 8 of 24 distinct role surfaces
//  (Driver, Shipper, Carrier, Broker, Catalyst, Escort, Terminal,
//  Admin) have at least one shipped screen in the registry. Replaces
//  the `RolePlaceholderScreen` stub the dev chrome was rendering for
//  `ProductionScreen.Role.admin`. Direct mirror of
//  `Views/Terminal/700_TerminalHome.swift` (107th firing) and
//  `Views/Escort/600_EscortHome.swift` (103rd) and the rest of the
//  Cohort B home anchors.
//
//  Admin owns platform-wide ops: tenant lifecycle, user lifecycle,
//  approvals, support tickets, experiments, and platform health per
//  the §16 admin-tenant-ops slice. The home re-frames the four-card
//  hierarchy around ticket flow + approvals queue rather than
//  movement flow / corridor coverage / match flow.
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
//    • KPI strip → `admin.getDashboardStats` via
//      `AdminHomeDashboardStore` (LiveDataStores.swift). Server
//      returns a six-figure envelope: activeTenants,
//      activeUsersThisWeek, pendingApprovals, supportTicketsOpen,
//      mrrThisMonth, systemHealthScore. Backend convention mirrors
//      `terminals.getDashboardStats`.
//    • "Needs your attention" alert strip →
//      `admin.getApprovalsRequiringAttention` via
//      `AdminAlertsStore`. Empty until the platform exception
//      engine flags a pending approval, failed integration, payment
//      exception, fraud signal, MFA enrollment lapse, or
//      blockchain-audit drift.
//    • "Open tickets" feed → `admin.getOpenTickets` via
//      `AdminOpenTicketsStore`.
//    • "Recent activity" feed → `admin.getRecentTickets` via
//      `AdminRecentTicketsStore`.
//    • Zero synthesised data. Each card switches over its store's
//      RemoteState; `.loading` shows a skeleton, `.empty` renders
//      `EusoEmptyState`, `.error` renders an inline retry, and
//      `.loaded` paints the real values. If the backend has not
//      yet exposed `admin.*`, every card resolves to `.error`
//      and offers retry — no placeholder data is ever shown,
//      satisfying doctrine §11 + `MockDataGuard`.
//
//  Note on §16-flagged endpoints: the iOS surface intentionally
//  does NOT consume `admin.impersonateUser` or the system-settings
//  endpoints flagged as mock-stubbed in the §16 admin-tenant-ops
//  slice. Only the legitimate dashboard envelope shapes above are
//  bound on this brick.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct AdminHome: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var dashboard = AdminHomeDashboardStore()
    @StateObject private var alerts    = AdminAlertsStore()
    @StateObject private var tickets   = AdminOpenTicketsStore()
    @StateObject private var recent    = AdminRecentTicketsStore()

    /// 802_AdminTenants sheet host. Opened by tapping the
    /// "View all →" CTA on the new ACTIVE TENANTS section header.
    /// Mirrors the 700→701 sheet doctrine (Terminal · Gate Queue).
    /// Added 2026-04-27 in the 151st eusotrip-killers firing alongside
    /// the 802 brick port — brings Admin to two-screen depth, parity
    /// with Terminal/Escort/Catalyst/Carrier/Broker.
    @State private var tenantsOpen: Bool = false

    /// 801_AdminControlTower sheet host. Opened by tapping the
    /// "Open tower →" CTA on the new PLATFORM CONTROL TOWER section
    /// header. Same `.sheet([.large])` doctrine as `tenantsOpen`.
    /// Added 2026-04-27 in the 156th eusotrip-killers firing alongside
    /// the 801 brick port — closes the 800→802 leapfrog gap and
    /// brings Admin to three-screen depth (parity with Terminal
    /// 700/701/702 and Catalyst 500/501/502).
    @State private var controlTowerOpen: Bool = false

    // ── Home-widget customization — uses shared HomeWidgetGrid. ──
    private let widgetLayoutKey = "admin.home.widgetOrder"
    private let adminCanonicalOrder: [String] = ["openTickets", "system_health", "pending_approvals", "recent", "news"]

    @ViewBuilder
    private func adminHomeRender(_ id: String) -> AnyView {
        switch id {
        case "openTickets":       AnyView(openTicketsCard)
        case "system_health":     AnyView(systemHealthWidget)
        case "pending_approvals": AnyView(pendingApprovalsWidget)
        case "recent":            AnyView(recentActivityCard)
        case "news":              AnyView(NewsCarouselWidget())
        default:                  AnyView(EmptyView())
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                controlTowerLink
                tenantsLink
                attentionStrip
                HomeWidgetGrid(
                    canonicalOrder: adminCanonicalOrder,
                    role: "ADMIN",
                    storageKey: widgetLayoutKey,
                    render: { id in adminHomeRender(id) }
                )
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .screenTileRoot()
        // 802_AdminTenants sheet — opened by the ACTIVE TENANTS
        // section header's "View all →" CTA. Detents `[.large]` +
        // drag indicator mirrors the 700→701 doctrine.
        .sheet(isPresented: $tenantsOpen) {
            AdminTenantsScreen(theme: palette)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // 801_AdminControlTower sheet — opened by the PLATFORM
        // CONTROL TOWER section header's "Open tower →" CTA. Same
        // detents + drag indicator as the tenants sheet.
        .sheet(isPresented: $controlTowerOpen) {
            AdminControlTowerScreen(theme: palette)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Control Tower section link
    //
    // Compact section header that exposes the 801 drill-down without
    // displacing the existing card layout. The active-exception count
    // comes from the home dashboard's `pendingApprovals` rollup as a
    // proxy until the control-tower pipeline lands its own count on
    // the home envelope; the deep exception list lives on 801 and is
    // fetched there on first open.
    private var controlTowerLink: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("PLATFORM CONTROL TOWER")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            if let outer = dashboard.state.value, let s = outer {
                Text("HEALTH \(Int((s.systemHealthScore * 100).rounded()))%")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            Button { controlTowerOpen = true } label: {
                HStack(spacing: 4) {
                    Text("Open tower")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tenants section link
    //
    // Compact section header that exposes the 802 drill-down without
    // displacing the existing card layout. The count comes off the
    // already-loaded `dashboard.activeTenants` rollup, so this row
    // doesn't issue its own round-trip; the deep tenant list lives
    // on 802 and is fetched there on first open.
    private var tenantsLink: some View {
        HStack(spacing: 6) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("ACTIVE TENANTS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            if let outer = dashboard.state.value, let s = outer {
                Text("\(s.activeTenants)")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            // 151st firing — tap opens 802_AdminTenants sheet.
            Button { tenantsOpen = true } label: {
                HStack(spacing: 4) {
                    Text("View all")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func refreshAll() async {
        async let a: Void = dashboard.refresh()
        async let b: Void = alerts.refresh()
        async let c: Void = tickets.refresh()
        async let d: Void = recent.refresh()
        _ = await (a, b, c, d)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.badge.key.fill")
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
                    Text("ADMIN · HOME")
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
            return "Eyes on the platform, \(name)"
        }
        return "Admin · Home"
    }

    private var subhead: String {
        if let outer = dashboard.state.value, let s = outer {
            let open = s.supportTicketsOpen
            let pending = s.pendingApprovals
            return "\(open) open ticket\(open == 1 ? "" : "s") · \(pending) approval\(pending == 1 ? "" : "s") pending"
        }
        return "Loading platform fabric…"
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
                    subtitle: "Once the first tenant or user signs in, the dashboard will populate with live platform metrics."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "chart.bar",
                title: "No KPIs yet",
                subtitle: "Once the first tenant or user signs in, the dashboard will populate with live platform metrics."
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

    private func kpiGrid(_ s: AdminAPI.DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            kpiTile(label: "ACTIVE TENANTS",   value: "\(s.activeTenants)",          sub: "30d distinct")
            kpiTile(label: "ACTIVE USERS · 7D",value: "\(s.activeUsersThisWeek)",    sub: "engaged this week")
            kpiTile(label: "OPEN TICKETS",     value: "\(s.supportTicketsOpen)",     sub: "unresolved")
            kpiTile(label: "PENDING APPROVALS",value: "\(s.pendingApprovals)",       sub: "awaiting decision")
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

    /// Format a health composite ratio (0.0…1.0) as a percentage
    /// rounded to whole digits. Returns "—" for zero so the empty
    /// case never renders as "0%".
    private func health(_ v: Double) -> String {
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

    private func alertRow(_ row: AdminAPI.AdminAlert) -> some View {
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
                Text(row.ticketNumber)
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

    // MARK: - Open tickets

    @ViewBuilder
    private var openTicketsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("OPEN TICKETS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = tickets.state {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            switch tickets.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { ticketRow($0) }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "ticket",
                    title: "No open tickets",
                    subtitle: "When a tenant or user opens a support ticket you'll see the priority and customer here in real time."
                )
            case .error(let e):
                inlineError(e) { Task { await tickets.refresh() } }
            }
        }
    }

    private func ticketRow(_ row: AdminAPI.ActiveTicket) -> some View {
        let priorityColor: Color = {
            switch row.priority.lowercased() {
            case "urgent":  return Brand.danger
            case "high":    return Brand.warning
            default:        return palette.textTertiary
            }
        }()
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.ticketNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(row.subject)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.customer)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Text("opened \(row.openedAt)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                if !row.status.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text(row.status.replacingOccurrences(of: "_", with: " ").uppercased())
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.priority.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(priorityColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(priorityColor.opacity(0.5), lineWidth: 1))
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
                    subtitle: "Once a ticket resolves or an approval clears, it'll show up here with the customer and final status."
                )
            case .error(let e):
                inlineError(e) { Task { await recent.refresh() } }
            }
        }
    }

    private func recentRow(_ row: AdminAPI.RecentTicket) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.ticketNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(row.subject)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                if !row.customer.isEmpty {
                    Text(row.customer)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.status.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
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

    // MARK: - System health widget

    @ViewBuilder
    private var systemHealthWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SYSTEM HEALTH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            switch dashboard.state {
            case .loading:
                listSkeleton
            case .loaded(let maybe):
                if let s = maybe {
                    HStack(spacing: Space.s2) {
                        kpiTile(label: "HEALTH SCORE", value: String(format: "%.0f%%", s.systemHealthScore * 100), sub: "platform health")
                        kpiTile(label: "TENANTS",      value: "\(s.activeTenants)",      sub: "active tenants")
                        kpiTile(label: "USERS · 7D",   value: "\(s.activeUsersThisWeek)", sub: "active this week")
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "waveform.path.ecg", title: "No health data",
                               subtitle: "Platform metrics will appear here once the system is active.")
            case .error(let e):
                inlineError(e) { Task { await dashboard.refresh() } }
            }
        }
    }

    // MARK: - Pending approvals widget

    @ViewBuilder
    private var pendingApprovalsWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "checklist.unchecked")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.warning)
                Text("PENDING APPROVALS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = alerts.state, !rows.isEmpty {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.warning))
                }
            }
            switch alerts.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.circle", title: "Nothing pending",
                                   subtitle: "No approvals require action right now.")
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(rows.prefix(3)) { alertRow($0) }
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "checkmark.circle", title: "Nothing pending",
                               subtitle: "No approvals require action right now.")
            case .error(let e):
                inlineError(e) { Task { await alerts.refresh() } }
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

struct AdminHomeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            AdminHome()
        } nav: {
            BottomNav(
                leading: adminNavLeading_800(),
                trailing: adminNavTrailing_800(),
                orbState: .idle
            )
        }
    }
}

private func adminNavLeading_800() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house.fill",        isCurrent: true),
     NavSlot(label: "Tickets", systemImage: "ticket.fill",       isCurrent: false)]
}

private func adminNavTrailing_800() -> [NavSlot] {
    [NavSlot(label: "Tenants", systemImage: "building.2",        isCurrent: false),
     NavSlot(label: "Me",      systemImage: "person",            isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// This is a doctrine §10 requirement (previews compile and render
// in isolation, no live API).

#Preview("800 · Admin · Home · Night") {
    AdminHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("800 · Admin · Home · Afternoon") {
    AdminHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
