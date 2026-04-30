//
//  801_AdminControlTower.swift
//  EusoTrip — Admin · Platform Control Tower (brick 801).
//
//  Third brick on the Admin role track (800s). Closes the 800->802
//  leapfrog gap and brings Admin to 3-deep parity with Terminal
//  (700/701/702) and Catalyst (500/501/502). Drilled into from the
//  new "PLATFORM CONTROL TOWER" section header on `800_AdminHome`,
//  presented as a `.sheet([.large])` so the home dashboard stays
//  underneath. The screen surfaces:
//
//    • KPI strip — six platform-health tiles from
//      `admin.controlTower.getOverview` (active exceptions,
//      breached-SLA exceptions, system-health composite, API SLO,
//      queue lag, error rate). Vendor-integration rollup is the
//      header chip (green / yellow / red).
//    • Severity-filter chip row (ALL · CRITICAL · URGENT · HIGH ·
//      NORMAL · LOW) — re-fetches the exception feed with a tighter
//      scope. Whitelist mirrors the server's `severity` enum.
//    • Exception feed list — `admin.controlTower.getExceptions`.
//      Each row carries a left-side gradient bar coloured by
//      severity, the headline + scope, the SLA chip (BREACHED /
//      AT RISK / ON TRACK), assignee, and an "Acknowledge" CTA
//      that calls `admin.controlTower.acknowledgeException` with
//      an optimistic flip from "breached" -> "at_risk" so the
//      operator gets sub-frame UI ack.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  accent — no `.fill(Brand.blue)` / `.tint(Brand.blue)`), §2 (no
//  Toggles on this brick), §3 (`AnyShapeStyle` wrapping for ternary
//  shape-styles in fill / stroke), §4 (tokenized spacing / radius /
//  type — Space.s*, Radius.*, EType.*), §5 (palette-semantic only —
//  no hard-coded `Color.white` / `Color.black` / `Color.gray` outside
//  CTA inverse-text + shadow opacities), §10 (previews compile in
//  isolation — `.task` doesn't run in the canvas, so the stores stay
//  in `.loading` and never hit the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • KPI strip → `AdminControlTowerOverviewStore` →
//      `admin.controlTower.getOverview`. nil + zero-rollup tuple
//      folds to `.empty` and the strip surfaces "Awaiting first
//      pipeline run" — never a row of fabricated zeros.
//    • Exception feed → `AdminControlTowerExceptionsStore` →
//      `admin.controlTower.getExceptions`. Empty + error states
//      surface neutral copy + retry CTA.
//    • Acknowledge → `admin.controlTower.acknowledgeException`
//      (mutation). Per-row in-flight latch + optimistic SLA flip
//      on success; rollback on error with a row-local banner.
//      Backend-miss = thrown error -> rollback -> retry banner.
//    • Every nullable column (`category`, `assignee`, `openedAt`)
//      renders as a neutral em-dash sentinel — never a fabricated
//      string. Numeric tiles fall back to "—" when the rollup is
//      .empty so the strip never reads as "0%/0s/0/0".
//
//  Wired into `ContentView.ScreenRegistry` as id="801".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Severity filter chip set
//
// Whitelist mirrors the server's `severity` enum on the
// `admin.controlTower.getExceptions` query. The "All" pseudo-value
// maps to nil on `AdminControlTowerExceptionsStore.severityFilter` —
// no filter (server returns every active exception). Order matches
// the operator's most-frequent inspection cadence: critical / urgent
// first (the breach risks), then the lower buckets.

private enum CTowerSeverityFilter: String, CaseIterable, Identifiable {
    case all
    case critical
    case urgent
    case high
    case normal
    case low

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "ALL"
        case .critical: return "CRITICAL"
        case .urgent:   return "URGENT"
        case .high:     return "HIGH"
        case .normal:   return "NORMAL"
        case .low:      return "LOW"
        }
    }

    /// Server-side enum value passed to
    /// `admin.controlTower.getExceptions`. nil = no filter.
    var serverValue: String? {
        switch self {
        case .all:      return nil
        case .critical: return "critical"
        case .urgent:   return "urgent"
        case .high:     return "high"
        case .normal:   return "normal"
        case .low:      return "low"
        }
    }
}

// MARK: - Screen body

struct AdminControlTower: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var overview = AdminControlTowerOverviewStore()
    @StateObject private var exceptions = AdminControlTowerExceptionsStore()

    /// Selected severity filter chip — drives a refresh on change.
    @State private var filter: CTowerSeverityFilter = .all

    /// Exceptions currently being acknowledged. Keyed by row id so
    /// an in-flight row's CTA disables (and shows a small spinner)
    /// while the mutation is flying.
    @State private var inflightAck: Set<String> = []

    /// Per-row local SLA override applied optimistically after a
    /// successful acknowledge. Server resolves to `at_risk` on the
    /// next pipeline run; until then we hold the optimistic value
    /// here so the row's chip flips immediately.
    @State private var localSLAOverride: [String: String] = [:]

    /// Per-row error message surfaced when an acknowledge mutation
    /// throws. Cleared on the next refresh.
    @State private var rowError: [String: String] = [:]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                filterRow
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
    }

    private func refreshAll() async {
        async let a: Void = overview.refresh()
        async let b: Void = exceptions.refresh()
        _ = await (a, b)
        // Refresh wipes optimistic local state — server is now the
        // truth (whatever the pipeline computed, the row chip
        // matches it on the next render).
        localSLAOverride.removeAll()
        rowError.removeAll()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
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
                        Text("ADMIN · CONTROL TOWER")
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
                vendorRollupChip
            }
            .padding(.top, 4)
        }
    }

    /// Identity-aware headline. Falls back to a neutral title so the
    /// header never reads as a placeholder.
    private var headline: String {
        if let name = session.user?.firstName, !name.isEmpty {
            return "Eyes on, \(name)"
        }
        return "Platform Control Tower"
    }

    private var subhead: String {
        switch overview.state {
        case .loading:
            return "Loading platform health…"
        case .loaded(let outer):
            guard let s = outer else { return "Platform health pipeline armed" }
            let last = s.lastUpdatedAt.isEmpty ? "" : " · updated \(s.lastUpdatedAt)"
            return "\(s.activeExceptionsCount) active · \(s.breachedSLAExceptionsCount) breached\(last)"
        case .empty:
            return "Awaiting first pipeline run"
        case .error:
            return "Health pipeline couldn't load"
        }
    }

    /// Vendor-integration rollup pill in the header. Mirrors
    /// the server's three-state rollup ("green", "yellow", "red")
    /// across Stripe + HERE + FMCSA + CBP + CBSA.
    private var vendorRollupChip: some View {
        let raw = overviewLoaded?.vendorIntegrationStatus.lowercased() ?? ""
        let label: String
        let style: AnyShapeStyle
        let fg: Color
        switch raw {
        case "green":
            label = "VENDORS · OK"
            style = AnyShapeStyle(LinearGradient.diagonal)
            fg = .white
        case "yellow":
            label = "VENDORS · WATCH"
            style = AnyShapeStyle(Brand.warning.opacity(0.18))
            fg = Brand.warning
        case "red":
            label = "VENDORS · DOWN"
            style = AnyShapeStyle(Brand.danger.opacity(0.18))
            fg = Brand.danger
        default:
            label = "VENDORS · —"
            style = AnyShapeStyle(palette.tintNeutral)
            fg = palette.textSecondary
        }
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(style)
            .clipShape(Capsule())
    }

    // MARK: - KPI strip
    //
    // Six tiles in a 3-column grid. Numeric tiles use the rollup
    // when `.loaded`, "—" when `.empty` or `.error`. The strip is
    // visible in every state (it's the operator's anchor); content
    // gracefully falls back, never mock-fills.

    private var kpiStrip: some View {
        let s = overviewLoaded
        return VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                kpiTile(
                    label: "ACTIVE",
                    value: s.map { "\($0.activeExceptionsCount)" } ?? "—",
                    accent: .gradient
                )
                kpiTile(
                    label: "BREACHED",
                    value: s.map { "\($0.breachedSLAExceptionsCount)" } ?? "—",
                    accent: (s?.breachedSLAExceptionsCount ?? 0) > 0 ? .danger : .neutral
                )
                kpiTile(
                    label: "HEALTH",
                    value: s.map { healthFmt($0.systemHealthScore) } ?? "—",
                    accent: healthAccent(s?.systemHealthScore)
                )
            }
            HStack(spacing: Space.s2) {
                kpiTile(
                    label: "API SLO 24H",
                    value: s.map { pctFmt($0.apiSLO24h) } ?? "—",
                    accent: .neutral
                )
                kpiTile(
                    label: "QUEUE LAG",
                    value: s.map { lagFmt($0.queueLagSeconds) } ?? "—",
                    accent: (s?.queueLagSeconds ?? 0) > 30 ? .warning : .neutral
                )
                kpiTile(
                    label: "ERR · 1H",
                    value: s.map { pctFmt($0.errorRate1h) } ?? "—",
                    accent: (s?.errorRate1h ?? 0) > 0.01 ? .danger : .neutral
                )
            }
        }
    }

    private enum KPIAccent {
        case gradient, neutral, warning, danger
    }

    private func kpiTile(label: String, value: String, accent: KPIAccent) -> some View {
        let valueStyle: AnyShapeStyle
        switch accent {
        case .gradient: valueStyle = AnyShapeStyle(LinearGradient.diagonal)
        case .neutral:  valueStyle = AnyShapeStyle(palette.textPrimary)
        case .warning:  valueStyle = AnyShapeStyle(Brand.warning)
        case .danger:   valueStyle = AnyShapeStyle(Brand.danger)
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(valueStyle)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Filter chip row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CTowerSeverityFilter.allCases) { f in
                    filterChip(f)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ f: CTowerSeverityFilter) -> some View {
        let isActive = (f == filter)
        return Button {
            guard f != filter else { return }
            filter = f
            exceptions.severityFilter = f.serverValue
            Task { await exceptions.refresh() }
        } label: {
            Text(f.label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(isActive ? Color.white : palette.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(isActive
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.bgCard))
                .overlay(
                    Capsule()
                        .strokeBorder(isActive
                                      ? AnyShapeStyle(Color.clear)
                                      : AnyShapeStyle(palette.borderFaint),
                                      lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch exceptions.state {
        case .loading:
            listSkeleton
        case .loaded(let rows):
            VStack(spacing: Space.s2) {
                ForEach(rows) { row in
                    exceptionRow(row)
                }
            }
        case .empty:
            EusoEmptyState(
                systemImage: "checkmark.shield",
                title: filter == .all ? "Nothing on the board" : "No \(filter.label.lowercased()) exceptions",
                subtitle: filter == .all
                    ? "Platform is quiet — no active exceptions on the operator's plate. The control tower watches every alert source in real time and surfaces them here as they open."
                    : "Try a wider severity filter, or pull to refresh."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - Exception row

    private func exceptionRow(_ row: AdminAPI.ControlTowerException) -> some View {
        let isInflight = inflightAck.contains(row.id)
        let resolvedSLA = localSLAOverride[row.id] ?? row.slaStatus
        let rowErr = rowError[row.id]
        return HStack(alignment: .top, spacing: 0) {
            // Left-side severity bar.
            severityBar(row.severity)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: Space.s2) {
                // Top: headline + SLA chip.
                HStack(alignment: .top, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.headline.isEmpty ? "—" : row.headline)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(2)
                        Text(row.scope.isEmpty ? "—" : row.scope)
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    slaChip(resolvedSLA)
                }

                // Middle: category + assignee + opened-at.
                HStack(spacing: 8) {
                    Image(systemName: categoryIcon(row.category))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.category.isEmpty ? "—" : row.category.uppercased())
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.assignee.isEmpty ? "—" : row.assignee)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Text("·").foregroundStyle(palette.textTertiary)
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text(row.openedAt.isEmpty ? "—" : row.openedAt)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }

                // Bottom: acknowledge CTA (or rowError banner).
                HStack(alignment: .center, spacing: Space.s3) {
                    Spacer()
                    if let msg = rowErr {
                        Text(msg)
                            .font(EType.caption)
                            .foregroundStyle(Brand.danger)
                            .lineLimit(1)
                    }
                    Button {
                        Task { await acknowledge(row) }
                    } label: {
                        HStack(spacing: 4) {
                            if isInflight {
                                ProgressView().controlSize(.mini).tint(Brand.magenta)
                            } else {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(LinearGradient.diagonal)
                            }
                            Text(isInflight ? "Acknowledging…" : "Acknowledge")
                                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(LinearGradient.diagonal)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isInflight || resolvedSLA.lowercased() != "breached")
                    .opacity(resolvedSLA.lowercased() == "breached" ? 1.0 : 0.4)
                }
            }
            .padding(Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Acknowledge flow

    private func acknowledge(_ row: AdminAPI.ControlTowerException) async {
        guard !inflightAck.contains(row.id) else { return }
        guard row.slaStatus.lowercased() == "breached" else { return }
        inflightAck.insert(row.id)
        rowError.removeValue(forKey: row.id)
        defer { inflightAck.remove(row.id) }
        do {
            _ = try await EusoTripAPI.shared.admin.acknowledgeControlTowerException(id: row.id)
            // Optimistic flip: BREACHED -> AT RISK. The next
            // pipeline tick reconciles the real state.
            localSLAOverride[row.id] = "at_risk"
        } catch {
            rowError[row.id] = readableError(error)
        }
    }

    // MARK: - Severity + SLA chips

    private func severityBar(_ severity: String) -> some View {
        let s = severity.lowercased()
        let style: AnyShapeStyle
        switch s {
        case "critical":
            style = AnyShapeStyle(Brand.danger)
        case "urgent":
            style = AnyShapeStyle(Brand.danger.opacity(0.65))
        case "high":
            style = AnyShapeStyle(Brand.warning)
        case "normal":
            style = AnyShapeStyle(LinearGradient.diagonal)
        case "low":
            style = AnyShapeStyle(palette.tintNeutral)
        default:
            style = AnyShapeStyle(palette.tintNeutral)
        }
        return Rectangle().fill(style)
    }

    private func slaChip(_ raw: String) -> some View {
        let normalized = raw.lowercased()
        let label: String
        let style: AnyShapeStyle
        let fg: Color
        switch normalized {
        case "breached":
            label = "BREACHED"
            style = AnyShapeStyle(Brand.danger.opacity(0.18))
            fg = Brand.danger
        case "at_risk":
            label = "AT RISK"
            style = AnyShapeStyle(Brand.warning.opacity(0.18))
            fg = Brand.warning
        case "on_track":
            label = "ON TRACK"
            style = AnyShapeStyle(LinearGradient.diagonal)
            fg = .white
        default:
            label = raw.isEmpty
                ? "—"
                : raw.replacingOccurrences(of: "_", with: " ").uppercased()
            style = AnyShapeStyle(palette.tintNeutral)
            fg = palette.textSecondary
        }
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style)
            .clipShape(Capsule())
    }

    private func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "infra":         return "server.rack"
        case "integration":   return "bolt.horizontal.circle"
        case "fraud":         return "shield.lefthalf.filled"
        case "billing":       return "creditcard"
        case "compliance":    return "checkmark.shield"
        case "support":       return "lifepreserver"
        case "security":      return "lock.shield"
        default:              return "exclamationmark.circle"
        }
    }

    // MARK: - Loading + error states

    private var listSkeleton: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 116)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: { Task { await refreshAll() } }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private var overviewLoaded: AdminAPI.ControlTowerOverview? {
        if case .loaded(let outer) = overview.state {
            return outer
        }
        return nil
    }

    private func healthFmt(_ score: Double) -> String {
        let pct = Int((score * 100).rounded())
        return "\(pct)%"
    }

    private func healthAccent(_ score: Double?) -> KPIAccent {
        guard let s = score else { return .neutral }
        if s >= 0.95 { return .gradient }
        if s >= 0.85 { return .neutral }
        if s >= 0.70 { return .warning }
        return .danger
    }

    private func pctFmt(_ v: Double) -> String {
        // SLO is expressed as a fraction (0.997 -> "99.7%"); error
        // rate likewise (0.012 -> "1.2%"). Use one decimal to keep
        // the operator's read accurate without crowding the tile.
        let pct = v * 100
        if pct >= 99.95 { return "100%" }
        return String(format: "%.1f%%", pct)
    }

    private func lagFmt(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let r = seconds % 60
        if r == 0 { return "\(m)m" }
        return "\(m)m \(r)s"
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct AdminControlTowerScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            AdminControlTower()
        } nav: {
            BottomNav(
                leading: adminNavLeading_801(),
                trailing: adminNavTrailing_801(),
                orbState: .idle
            )
        }
    }
}

private func adminNavLeading_801() -> [NavSlot] {
    [NavSlot(label: "Home",    systemImage: "house",         isCurrent: false),
     NavSlot(label: "Tickets", systemImage: "ticket.fill",   isCurrent: false)]
}

private func adminNavTrailing_801() -> [NavSlot] {
    [NavSlot(label: "Tower",   systemImage: "scope",           isCurrent: true),
     NavSlot(label: "Tenants", systemImage: "building.2.fill", isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the stores stay in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("801 · Admin · Control Tower · Night") {
    AdminControlTowerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("801 · Admin · Control Tower · Afternoon") {
    AdminControlTowerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
