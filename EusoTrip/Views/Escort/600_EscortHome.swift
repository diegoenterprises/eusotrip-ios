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

    // ── Home-widget customization (2026-05-23 · DnD parity) ──
    enum EscortWidgetSlot: String, CaseIterable, Codable, Identifiable {
        case activeAssignments, recent, news
        var id: String { rawValue }
        var label: String {
            switch self {
            case .activeAssignments: return "Active assignments"
            case .recent:            return "Recent activity"
            case .news:              return "Escort intel"
            }
        }
    }
    @State private var widgetOrder: [EscortWidgetSlot] = EscortWidgetSlot.allCases
    @State private var editingLayout: Bool = false
    @State private var dropHoverSlot: EscortWidgetSlot? = nil
    private let widgetLayoutKey = "escort.home.widgetOrder"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                attentionStrip
                widgetZoneToolbar
                ForEach(widgetOrder) { slot in
                    secondaryWidget(for: slot)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            await refreshAll()
            await hydrateWidgetLayout()
        }
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

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
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
                    Text("ESCORT · HOME")
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
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
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
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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

    // MARK: - Reorderable secondary-widget zone (DnD parity)

    private var widgetZoneToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: editingLayout ? "checkmark.circle.fill" : "rectangle.3.group.bubble")
                .font(.system(size: 11, weight: .heavy))
            Text(editingLayout ? "DONE · Tap to save layout" : "CUSTOMIZE WIDGETS")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            Spacer(minLength: 0)
            if editingLayout {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { widgetOrder = EscortWidgetSlot.allCases }
                } label: {
                    Text("RESET")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(palette.bgCard, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(editingLayout ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
        .padding(.horizontal, Space.s3).padding(.vertical, 8)
        .background(
            Capsule().strokeBorder(
                editingLayout ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                lineWidth: 1
            )
        )
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) {
                if editingLayout { editingLayout = false; Task { await persistWidgetLayout() } }
                else { editingLayout = true }
            }
        }
    }

    @ViewBuilder
    private func secondaryWidget(for slot: EscortWidgetSlot) -> some View {
        let inner: AnyView = {
            switch slot {
            case .activeAssignments: return AnyView(activeAssignmentsCard)
            case .recent:            return AnyView(recentActivityCard)
            case .news:              return AnyView(NewsCarouselWidget())
            }
        }()
        if editingLayout {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 10)
                inner
            }
            .overlay(alignment: .topTrailing) {
                Text(slot.label.uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
                    .padding(6)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        dropHoverSlot == slot ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: dropHoverSlot == slot ? 2 : 1
                    )
                    .animation(.easeOut(duration: 0.12), value: dropHoverSlot)
            )
            .draggable(slot.rawValue) {
                Text(slot.label)
                    .font(.system(size: 13, weight: .heavy))
                    .padding(10)
                    .background(palette.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
            }
            .dropDestination(for: String.self) { droppedIds, _ in
                guard let raw = droppedIds.first,
                      let dropped = EscortWidgetSlot(rawValue: raw),
                      dropped != slot,
                      let fromIdx = widgetOrder.firstIndex(of: dropped),
                      let toIdx = widgetOrder.firstIndex(of: slot)
                else { return false }
                withAnimation(.easeOut(duration: 0.18)) {
                    let item = widgetOrder.remove(at: fromIdx)
                    widgetOrder.insert(item, at: min(toIdx, widgetOrder.count))
                }
                return true
            } isTargeted: { hovering in
                dropHoverSlot = hovering ? slot : (dropHoverSlot == slot ? nil : dropHoverSlot)
            }
        } else {
            inner
        }
    }

    private func hydrateWidgetLayout() async {
        if let data = UserDefaults.standard.data(forKey: widgetLayoutKey),
           let cached = try? JSONDecoder().decode([EscortWidgetSlot].self, from: data),
           !cached.isEmpty {
            widgetOrder = reconcile(cached)
        }
        struct In: Encodable { let role: String }
        struct Slot: Decodable { let widgetId: String }
        struct Out: Decodable { let layout: [Slot]?; let updatedAt: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("users.getDashboardLayout", input: In(role: "ESCORT"))
            if let server = r.layout, !server.isEmpty {
                let parsed = server.compactMap { EscortWidgetSlot(rawValue: $0.widgetId) }
                if !parsed.isEmpty {
                    let merged = reconcile(parsed)
                    await MainActor.run { widgetOrder = merged }
                    if let data = try? JSONEncoder().encode(merged) {
                        UserDefaults.standard.set(data, forKey: widgetLayoutKey)
                    }
                }
            }
        } catch { }
    }

    private func persistWidgetLayout() async {
        if let data = try? JSONEncoder().encode(widgetOrder) {
            UserDefaults.standard.set(data, forKey: widgetLayoutKey)
        }
        struct Slot: Encodable { let widgetId: String; let x: Int; let y: Int; let w: Int; let h: Int }
        struct In: Encodable { let role: String; let layout: [Slot] }
        struct Out: Decodable { let success: Bool? }
        let payload = widgetOrder.enumerated().map { idx, slot in
            Slot(widgetId: slot.rawValue, x: 0, y: idx, w: 12, h: 4)
        }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "users.saveDashboardLayout",
                input: In(role: "ESCORT", layout: payload)
            )
        } catch { }
    }

    private func reconcile(_ saved: [EscortWidgetSlot]) -> [EscortWidgetSlot] {
        var seen = Set<EscortWidgetSlot>(); var out: [EscortWidgetSlot] = []
        for s in saved where !seen.contains(s) { out.append(s); seen.insert(s) }
        for s in EscortWidgetSlot.allCases where !seen.contains(s) { out.append(s) }
        return out
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
