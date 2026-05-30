//
//  600_EscortHome.swift
//  EusoTrip — Escort · Home (brick 600).
//
//  First brick on the Escort role track (600s). Replaces the
//  `RolePlaceholderScreen` stub the dev chrome was rendering for
//  `ProductionScreen.Role.escort`. Direct mirror of
//  `Views/Catalyst/500_CatalystHome.swift` shipped in the 102nd firing
//  (which itself mirrored Broker · 400 → Carrier · 300 → Shipper · 200).
//
//  Escort is the regulated-corridor pilot-car / safety-escort operator
//  surface — the role that runs the high-and-wide / oversize / OS-OW
//  permit corridors per the EusoTrip backend §16 compliance-safety slice
//  (`escortOverview`, `escort_*` tables, bridge clearance integration).
//  The home re-frames the four-card hierarchy around live assignment
//  flow + corridor coverage rather than match flow or tender flow.
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
//    • KPI strip → `escorts.getDashboardStats` via
//      `EscortHomeDashboardStore` (LiveDataStores.swift). Server
//      returns a six-figure envelope: activeAssignments,
//      completedThisWeek, milesThisWeek, corridorCoverage,
//      onTimeRate, revenueThisWeek. Backend convention mirrors
//      `catalysts.getDashboardStats`.
//    • "Needs your attention" alert strip →
//      `escorts.getLoadsRequiringAttention` via
//      `EscortAlertsStore`. Empty until the escort-corridor
//      exception engine flags a clearance breach, route deviation,
//      escort handoff stall, lead/chase imbalance, or permit drift.
//    • "Active assignments" feed → `escorts.getActiveAssignments`
//      via `EscortActiveAssignmentsStore`.
//    • "Recent activity" feed → `escorts.getRecentAssignments` via
//      `EscortRecentAssignmentsStore`.
//    • Zero synthesised data. Each card switches over its store's
//      RemoteState; `.loading` shows a skeleton, `.empty` renders
//      `EusoEmptyState`, `.error` renders an inline retry, and
//      `.loaded` paints the real values. If the backend has not
//      yet exposed `escorts.*`, every card resolves to `.error`
//      and offers retry — no placeholder data is ever shown,
//      satisfying doctrine §11 + `MockDataGuard`.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct EscortHome: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var dashboard   = EscortHomeDashboardStore()
    @StateObject private var alerts      = EscortAlertsStore()
    @StateObject private var assignments = EscortActiveAssignmentsStore()
    @StateObject private var recent      = EscortRecentAssignmentsStore()

    /// Row currently presenting the 601_EscortAssignmentDetail sheet.
    /// `nil` while no row is selected. Wired in the 147th eusotrip-killers
    /// firing alongside the 601 brick.
    @State private var detailRow: EscortAPI.ActiveAssignment? = nil

    // ── Home-widget customization — uses shared HomeWidgetGrid. ──
    private let widgetLayoutKey = "escort.home.widgetOrder"
    private let escortCanonicalOrder: [String] = ["activeAssignments", "escort_revenue", "escort_alerts", "recent", "news"]

    private func escortHomeRender(_ id: String) -> AnyView {
        switch id {
        case "activeAssignments": AnyView(activeAssignmentsCard)
        case "escort_revenue":    AnyView(escortRevenueWidget)
        case "escort_alerts":     AnyView(escortAlertsWidget)
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
                attentionStrip
                HomeWidgetGrid(
                    canonicalOrder: escortCanonicalOrder,
                    role: "ESCORT",
                    storageKey: widgetLayoutKey,
                    render: { id in escortHomeRender(id) }
                )
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .screenTileRoot()
        // 601_EscortAssignmentDetail sheet — opened by tapping an
        // active-assignment row. Detents `[.large]` + drag indicator
        // mirrors the Driver-Me sub-route sheet doctrine.
        .sheet(item: $detailRow) { row in
            assignmentDetailSheet(for: row)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Tap on an active-assignment row presents the live
    /// 601_EscortAssignmentDetail surface. Every preview hint from
    /// the ActiveAssignment row carries through so the sheet has
    /// paint-1 visible content while `escorts.getActiveAssignmentDetail`
    /// resolves. The detail view internally renders em-dash sentinels
    /// for every blank server field per §13 no-fake-data doctrine.
    @ViewBuilder
    private func assignmentDetailSheet(for row: EscortAPI.ActiveAssignment) -> some View {
        EscortAssignmentDetailScreen(
            theme: palette,
            assignmentId: row.id,
            previewLoadNumber: row.loadNumber,
            previewLane: "\(row.origin) → \(row.destination)",
            previewStartedAt: row.startedAt,
            previewEscortRole: row.escortRole.isEmpty ? nil : row.escortRole,
            previewPermitNumber: row.permitNumber.isEmpty ? nil : row.permitNumber,
            previewCorridorCoverage: row.corridorCoverage > 0 ? row.corridorCoverage : nil
        )
        .environmentObject(session)
    }

    private func refreshAll() async {
        async let a: Void = dashboard.refresh()
        async let b: Void = alerts.refresh()
        async let c: Void = assignments.refresh()
        async let d: Void = recent.refresh()
        _ = await (a, b, c, d)
    }

    // MARK: - Header
    //
    // Bespoke hero header matching the 010_DriverHome idiom (the gold
    // standard merged in the bespoke-homes lane): a gradient eyebrow
    // role-chip row ("✦ ESCORT · DASHBOARD") balanced by a tertiary
    // context caps line on the right, then a heavy display greeting in
    // the brand diagonal gradient and a tertiary sub-context line. The
    // sparkle glyph rides the eyebrow exactly once per surface (§4.3
    // budget). Split into `eyebrowRow` + `headerRow` so the new chip can
    // sit above the greeting without exploding the type-check budget on
    // one giant view literal.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            eyebrowRow
            headerRow
        }
        .padding(.top, Space.s1)
    }

    /// Gradient role chip + tertiary live-context caps — the SVG-family
    /// header motif shared with Driver-010 / Shipper-200 so every role
    /// home reads as one family.
    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · DASHBOARD")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(contextCaps)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Identity gem + two-line greeting/sub. The gem keeps the original
    /// shield glyph but lifts onto the bespoke EusoCard surface; the
    /// greeting moves to the brand diagonal gradient so the hero reads
    /// EusoTrip-native in both Night and Afternoon.
    private var headerRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 40, height: 40)
                .eusoCard(radius: Radius.md, intensity: .whisper)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subhead)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    /// Right-rail context caps line. Surfaces the live assignment count
    /// when the dashboard has resolved, falling back to the role label
    /// so the eyebrow never reads as a placeholder.
    private var contextCaps: String {
        if let outer = dashboard.state.value, let s = outer {
            let live = s.activeAssignments
            return "ON THE CORRIDOR · \(live) LIVE"
        }
        return "ON THE CORRIDOR"
    }

    /// Identity-aware headline. Falls back to the role label so the
    /// header never reads as a placeholder.
    private var headline: String {
        if let name = session.user?.firstName, !name.isEmpty {
            return "On the corridor, \(name)"
        }
        return "Escort · Home"
    }

    private var subhead: String {
        if let outer = dashboard.state.value, let s = outer {
            let live = s.activeAssignments
            let week = s.completedThisWeek
            return "\(live) live assignment\(live == 1 ? "" : "s") · \(week) completed · 7d"
        }
        return "Loading corridor fabric…"
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
                    subtitle: "Once your first escort assignment is dispatched, the dashboard will populate the moment the corridor opens."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "chart.bar",
                title: "No KPIs yet",
                subtitle: "Once your first escort assignment is dispatched, the dashboard will populate the moment the corridor opens."
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
                    .eusoCard(radius: Radius.lg, intensity: .whisper)
            }
        }
    }

    private func kpiGrid(_ s: EscortAPI.DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            kpiTile(label: "ACTIVE ASSIGNMENTS", value: "\(s.activeAssignments)",   sub: "in-corridor")
            kpiTile(label: "COMPLETED · 7D",     value: "\(s.completedThisWeek)",   sub: "deliveries piloted")
            kpiTile(label: "MILES · 7D",         value: miles(s.milesThisWeek),     sub: "corridor mileage")
            kpiTile(label: "REVENUE · 7D",       value: dollars(s.revenueThisWeek), sub: "lane revenue · 7d")
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
        .eusoCard(radius: Radius.lg)
    }

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    /// Format escort-corridor mileage as a thousands-separated whole-mile
    /// string. Returns "—" for zero so the empty case never renders as
    /// "0 mi".
    private func miles(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let core = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        return "\(core) mi"
    }

    /// Format a corridor-coverage ratio (0.0…1.0) as a percentage
    /// rounded to whole digits. Returns "—" for zero so the empty
    /// case never renders as "0%".
    private func coverage(_ v: Double) -> String {
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
                    alertRow(row)
                }
            }
        case .error(let e):
            inlineError(e) { Task { await alerts.refresh() } }
        }
    }

    private func alertRow(_ row: EscortAPI.LoadAlert) -> some View {
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
        .eusoRow(radius: Radius.md)
    }

    // MARK: - Active assignments

    @ViewBuilder
    private var activeAssignmentsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ACTIVE ASSIGNMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = assignments.state {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            switch assignments.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { row in
                        // 147th eusotrip-killers firing — tap routes to
                        // 601_EscortAssignmentDetail. Wraps the row body
                        // in a `Button` so the underlying card visuals
                        // are unchanged but the surface is now
                        // tap-actionable.
                        Button {
                            detailRow = row
                        } label: {
                            assignmentRow(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "shield.lefthalf.filled",
                    title: "No live assignments",
                    subtitle: "When a load is dispatched onto your corridor you'll see the lead/chase pairing here in real time."
                )
            case .error(let e):
                inlineError(e) { Task { await assignments.refresh() } }
            }
        }
    }

    private func assignmentRow(_ row: EscortAPI.ActiveAssignment) -> some View {
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
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.escortRole.uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Text("started \(row.startedAt)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                if !row.permitNumber.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.gearshape.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text("Permit \(row.permitNumber)")
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
                if row.corridorCoverage > 0 {
                    Text(coverage(row.corridorCoverage))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("coverage")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .eusoRow(radius: Radius.md)
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
                    subtitle: "Once an escort assignment closes or a corridor delivers, it'll show up here with the lane and final coverage."
                )
            case .error(let e):
                inlineError(e) { Task { await recent.refresh() } }
            }
        }
    }

    private func recentRow(_ row: EscortAPI.RecentAssignment) -> some View {
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
                if row.finalCoverage > 0 {
                    Text(coverage(row.finalCoverage))
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
        .eusoRow(radius: Radius.md)
    }

    // MARK: - Shared widgets

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 56)
                    .eusoRow(radius: Radius.md)
            }
        }
    }

    // MARK: - Escort revenue widget

    @ViewBuilder
    private var escortRevenueWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("REVENUE SUMMARY")
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
                        kpiTile(label: "REVENUE · 7D", value: dollars(s.revenueThisWeek), sub: "net this week")
                        kpiTile(label: "ON-TIME",      value: String(format: "%.1f%%", s.onTimeRate * 100), sub: "delivery rate")
                        kpiTile(label: "MILES · 7D",   value: "\(s.milesThisWeek) mi", sub: "driven this week")
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "banknote", title: "No revenue data",
                               subtitle: "Complete an assignment and this week's revenue will appear here.")
            case .error(let e):
                inlineError(e) { Task { await dashboard.refresh() } }
            }
        }
    }

    // MARK: - Escort alerts widget

    @ViewBuilder
    private var escortAlertsWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.danger)
                Text("ESCORT ALERTS")
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
                                   subtitle: "No assignments need attention right now.")
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(rows.prefix(3)) { alertRow($0) }
                    }
                }
            case .empty:
                EusoEmptyState(systemImage: "checkmark.circle", title: "All clear",
                               subtitle: "No assignments need attention right now.")
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

struct EscortHomeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortHome()
        } nav: {
            BottomNav(
                leading: escortNavLeading_600(),
                trailing: escortNavTrailing_600(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_600() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house.fill",                 isCurrent: true),
     NavSlot(label: "Assignments", systemImage: "shield.lefthalf.filled",     isCurrent: false)]
}

private func escortNavTrailing_600() -> [NavSlot] {
    [NavSlot(label: "Corridor", systemImage: "map", isCurrent: false),
     NavSlot(label: "Me",       systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// This is a doctrine §10 requirement (previews compile and render
// in isolation, no live API).

#Preview("600 · Escort · Home · Night") {
    EscortHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("600 · Escort · Home · Afternoon") {
    EscortHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
