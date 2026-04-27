//
//  700_TerminalHome.swift
//  EusoTrip — Terminal · Home (brick 700).
//
//  First brick on the Terminal Manager role track (700s). Replaces
//  the `RolePlaceholderScreen` stub the dev chrome was rendering for
//  `ProductionScreen.Role.terminal`. Direct mirror of
//  `Views/Escort/600_EscortHome.swift` (103rd firing) and
//  `Views/Catalyst/500_CatalystHome.swift` (102nd) and Broker/Carrier/
//  Shipper home anchors.
//
//  Terminal Manager owns the port/yard ops surface — gate-in/gate-out
//  flow, container movements between staging/dock/rail spur, dock
//  assignment + dwell + demurrage exposure, and hazmat clearance per
//  the §16 admin-tenant-ops + intermodal-xborder + compliance-safety
//  slices. The home re-frames the four-card hierarchy around movement
//  flow + dwell rather than match flow / corridor coverage / tender
//  flow.
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
//    • KPI strip → `terminals.getDashboardStats` via
//      `TerminalHomeDashboardStore` (LiveDataStores.swift). Server
//      returns a six-figure envelope: activeMovements,
//      completedThisWeek, avgDwellHoursThisWeek, throughputThisWeek,
//      onTimeRate, gateUtilization. Backend convention mirrors
//      `escorts.getDashboardStats`.
//    • "Needs your attention" alert strip →
//      `terminals.getMovementsRequiringAttention` via
//      `TerminalAlertsStore`. Empty until the terminal exception
//      engine flags a dwell breach, demurrage exposure, dock
//      conflict, hazmat clearance pending, BOL mismatch, ISF 10+2
//      hold, or appointment drift.
//    • "Active movements" feed → `terminals.getActiveMovements`
//      via `TerminalActiveMovementsStore`.
//    • "Recent activity" feed → `terminals.getRecentMovements` via
//      `TerminalRecentMovementsStore`.
//    • Zero synthesised data. Each card switches over its store's
//      RemoteState; `.loading` shows a skeleton, `.empty` renders
//      `EusoEmptyState`, `.error` renders an inline retry, and
//      `.loaded` paints the real values. If the backend has not
//      yet exposed `terminals.*`, every card resolves to `.error`
//      and offers retry — no placeholder data is ever shown,
//      satisfying doctrine §11 + `MockDataGuard`.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct TerminalHome: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var dashboard = TerminalHomeDashboardStore()
    @StateObject private var alerts    = TerminalAlertsStore()
    @StateObject private var movements = TerminalActiveMovementsStore()
    @StateObject private var recent    = TerminalRecentMovementsStore()

    /// Whether the 701_TerminalGateQueue detail sheet is currently
    /// presenting. Wired in the 150th eusotrip-killers firing alongside
    /// the 701 brick — the active-movements section header now opens
    /// the deep gate-queue surface where each row gets an inline
    /// "Assign dock" CTA. This brings Terminal to two-screen depth,
    /// parity with Escort 600 → 601.
    @State private var gateQueueOpen: Bool = false

    /// Whether the 702_TerminalYardMap detail sheet is currently
    /// presenting. Wired in the 154th eusotrip-killers firing alongside
    /// the 702 brick — the KPI strip's "View yard →" CTA opens the
    /// full yard map. This brings Terminal to three-screen depth,
    /// honoring the user's "every screen each role at a time" cadence
    /// (700 home → 701 gate-queue detail → 702 yard-map detail).
    @State private var yardMapOpen: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                attentionStrip
                activeMovementsCard
                recentActivityCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
        .screenTileRoot()
        // 701_TerminalGateQueue sheet — opened by tapping the
        // "View queue →" CTA on the active-movements section header.
        // Detents `[.large]` + drag indicator mirrors the established
        // Driver-Me sub-route + Escort 601 sheet doctrine.
        .sheet(isPresented: $gateQueueOpen) {
            TerminalGateQueueScreen(theme: palette)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // 702_TerminalYardMap sheet — opened by tapping the trailing
        // "View yard →" header CTA on the home. Detents `[.large]` +
        // drag indicator matches the 701 doctrine so the two Terminal
        // detail surfaces feel structurally identical.
        .sheet(isPresented: $yardMapOpen) {
            TerminalYardMapScreen(theme: palette)
                .environmentObject(session)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func refreshAll() async {
        async let a: Void = dashboard.refresh()
        async let b: Void = alerts.refresh()
        async let c: Void = movements.refresh()
        async let d: Void = recent.refresh()
        _ = await (a, b, c, d)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "building.2.fill")
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
                    Text("TERMINAL · HOME")
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
            return "On the yard, \(name)"
        }
        return "Terminal · Home"
    }

    private var subhead: String {
        if let outer = dashboard.state.value, let s = outer {
            let live = s.activeMovements
            let week = s.completedThisWeek
            return "\(live) live movement\(live == 1 ? "" : "s") · \(week) gated out · 7d"
        }
        return "Loading yard fabric…"
    }

    // MARK: - KPI strip

    @ViewBuilder
    private var kpiStrip: some View {
        switch dashboard.state {
        case .loading:
            kpiSkeleton
        case .loaded(let maybe):
            if let s = maybe {
                VStack(alignment: .leading, spacing: Space.s2) {
                    kpiGrid(s)
                    yardMapCTA
                }
            } else {
                EusoEmptyState(
                    systemImage: "chart.bar",
                    title: "No KPIs yet",
                    subtitle: "Once your first truck or container clears the gate, the dashboard will populate the moment the yard opens."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "chart.bar",
                title: "No KPIs yet",
                subtitle: "Once your first truck or container clears the gate, the dashboard will populate the moment the yard opens."
            )
        case .error(let e):
            inlineError(e) { Task { await dashboard.refresh() } }
        }
    }

    /// "View yard map →" drill-in CTA. Wired in the 154th eusotrip-killers
    /// firing — opens the 702_TerminalYardMap sheet so the operator can
    /// see slot-level occupancy and release slots directly. Mirrors the
    /// 701 "View queue →" CTA pattern: gradient text, plain button,
    /// no decorative chrome.
    private var yardMapCTA: some View {
        HStack {
            Spacer()
            Button { yardMapOpen = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("View yard map")
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

    private func kpiGrid(_ s: TerminalAPI.DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s2),
                            GridItem(.flexible(), spacing: Space.s2)],
                  spacing: Space.s2) {
            kpiTile(label: "ACTIVE MOVEMENTS", value: "\(s.activeMovements)",          sub: "in-yard")
            kpiTile(label: "GATED OUT · 7D",   value: "\(s.completedThisWeek)",        sub: "movements resolved")
            kpiTile(label: "AVG DWELL · 7D",   value: dwell(s.avgDwellHoursThisWeek),  sub: "yard residency")
            kpiTile(label: "THROUGHPUT · 7D",  value: "\(s.throughputThisWeek)",       sub: "events processed")
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

    /// Format dwell hours as a one-decimal label. Returns "—" for
    /// zero so the empty case never renders as "0.0 hr".
    private func dwell(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        return String(format: "%.1f hr", v)
    }

    /// Format a utilization ratio (0.0…1.0) as a percentage rounded
    /// to whole digits. Returns "—" for zero so the empty case
    /// never renders as "0%".
    private func utilization(_ v: Double) -> String {
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

    private func alertRow(_ row: TerminalAPI.MovementAlert) -> some View {
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

    // MARK: - Active movements

    @ViewBuilder
    private var activeMovementsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ACTIVE MOVEMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if case .loaded(let rows) = movements.state {
                    Text("\(rows.count)")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                // 150th firing — tap opens 701_TerminalGateQueue sheet
                // for the deep queue + per-row "Assign dock" mutation.
                Button { gateQueueOpen = true } label: {
                    HStack(spacing: 4) {
                        Text("View queue")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(LinearGradient.diagonal)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                .buttonStyle(.plain)
            }
            switch movements.state {
            case .loading:
                listSkeleton
            case .loaded(let rows):
                VStack(spacing: Space.s2) {
                    ForEach(rows) { movementRow($0) }
                }
            case .empty:
                EusoEmptyState(
                    systemImage: "shippingbox",
                    title: "No live movements",
                    subtitle: "When a truck or container clears the gate you'll see the dock assignment and dwell here in real time."
                )
            case .error(let e):
                inlineError(e) { Task { await movements.refresh() } }
            }
        }
    }

    private func movementRow(_ row: TerminalAPI.ActiveMovement) -> some View {
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
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.stage.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Text("arrived \(row.arrivedAt)")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                }
                if !row.dockAssignment.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text("Dock \(row.dockAssignment)")
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
                if row.dwellHours > 0 {
                    Text(dwell(row.dwellHours))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("dwell")
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
                    subtitle: "Once a movement gates out or a container resolves, it'll show up here with the lane and final dwell."
                )
            case .error(let e):
                inlineError(e) { Task { await recent.refresh() } }
            }
        }
    }

    private func recentRow(_ row: TerminalAPI.RecentMovement) -> some View {
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
                if row.finalDwellHours > 0 {
                    Text(dwell(row.finalDwellHours))
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
}

// MARK: - Screen wrapper

struct TerminalHomeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TerminalHome()
        } nav: {
            BottomNav(
                leading: terminalNavLeading_700(),
                trailing: terminalNavTrailing_700(),
                orbState: .idle
            )
        }
    }
}

private func terminalNavLeading_700() -> [NavSlot] {
    [NavSlot(label: "Home",      systemImage: "house.fill",      isCurrent: true),
     NavSlot(label: "Movements", systemImage: "shippingbox.fill", isCurrent: false)]
}

private func terminalNavTrailing_700() -> [NavSlot] {
    [NavSlot(label: "Yard", systemImage: "map",    isCurrent: false),
     NavSlot(label: "Me",   systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so each store stays in `.loading` —
// both registers render the skeleton without hitting the network.
// This is a doctrine §10 requirement (previews compile and render
// in isolation, no live API).

#Preview("700 · Terminal · Home · Night") {
    TerminalHomeScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("700 · Terminal · Home · Afternoon") {
    TerminalHomeScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
