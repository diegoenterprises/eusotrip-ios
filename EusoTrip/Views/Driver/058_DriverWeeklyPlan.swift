//
//  058_DriverWeeklyPlan.swift
//  EusoTrip 2027 UI — Wave 7 (driver · weekly plan)
//
//  Screen 058 · Driver Weekly Plan — the driver's weekly roster + recent
//  performance hub. Combines two already-declared live stores so the
//  screen lands in Cohort B (fully dynamic) from day one, per the 54th
//  firing hand-off:
//
//    • `MyLoadsStore`        · `loads.search(status:, limit:)`
//    • `WeeklyEarningsStore` · `earnings.getWeeklySummaries(weeks:)`
//
//  Cohort-B dynamization · zero mock data, zero stubs
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data" clause):
//
//    • Every load number, origin, destination, rate, pickup date, cargo
//      label, and status pill on-screen is rendered from `MyLoadsStore`.
//      When the server returns `[]` the branded `EusoEmptyState` is
//      surfaced — the screen never invents a placeholder load.
//
//    • Every bar on the weekly earnings chart is rendered from
//      `WeeklyEarningsStore`. A brand-new driver with zero settled weeks
//      renders the empty-chart branch — no hardcoded demo bars.
//
//    • The "week range" header uses `Calendar.current` to derive the
//      driver's current ISO week locally — no server trip required and
//      no hardcoded dates.
//
//    • Bucket picker flips `MyLoadsStore.bucket` which triggers a store
//      `refresh()` via the `didSet` observer in LiveDataStores.swift — a
//      real network round-trip on every tap, no client-side filtering of
//      a cached local array.
//
//  Doctrine refs:
//    §2  Gradient-only brand accents — bucket selection, chart bars,
//        action-row icons all use `LinearGradient.diagonal`. No flat
//        `Brand.info` / `Brand.blue` fills anywhere.
//    §3  Every ternary shape expression is wrapped in `AnyShapeStyle(…)`.
//    §4  Brick recipe — tokenized spacing (Space.sN), tokenized radii,
//        tokenized type (EType.*).
//    §5  Palette semantic (`palette.textPrimary/Secondary/Tertiary`,
//        `palette.bgCard/bgPage`, `palette.borderFaint/Strong`) — never
//        `Color.white` / `Color.gray`.
//    §9  No dead buttons — every Button has a real production action,
//        and the "View full earnings" CTA is disabled without a loaded
//        state (can't route into a screen that has no data yet).
//    §10 Both previews compile in isolation — instantiate the live-store
//        path with an unauthenticated `EusoTripSession()`; both stores
//        resolve deterministically to `.empty` without the network.
//
//  Not in scope (follow-up firings):
//    • Editing a load from this surface (needs `loads.update` — already
//      covered by the LoadDetailSheet on the dispatch board).
//    • Per-day breakdown charts (the weekly aggregate is what the router
//      surfaces today; a daily view would need `earnings.getDailySummaries`
//      which does not yet ship).
//    • Cross-mode picker (truck vs rail vs vessel) — the server already
//      mode-gates based on the driver's `transportModes`; the surface
//      itself is mode-agnostic.
//

import SwiftUI

// MARK: - Screen

struct DriverWeeklyPlan: View {
    @Environment(\.palette) var palette

    @EnvironmentObject private var session: EusoTripSession

    // MARK: Live stores (both declared in LiveDataStores.swift)
    @StateObject private var loadsStore = MyLoadsStore()
    @StateObject private var earningsStore = WeeklyEarningsStore()

    // MARK: Local UI state
    @State private var bucket: MyLoadsStore.Bucket = .active

    /// Set true when the driver taps "View full earnings breakdown" —
    /// the sheet hosts the live `MeEarnings068` surface, same store
    /// ownership rules as every other Me sub-route (`.large` detent,
    /// visible drag indicator).
    @State private var showEarningsSheet = false

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                topBar
                bucketPicker
                loadsSection
                earningsSection
                actionRows
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .refreshable {
            await refreshAll()
        }
        .task {
            loadsStore.bucket = bucket
            await refreshAll()
        }
        .onChange(of: bucket) { _, new in
            // MyLoadsStore's `didSet` on `bucket` re-fires its own
            // refresh; we assign here and let the store drive the
            // round-trip so there's a single source of truth.
            loadsStore.bucket = new
        }
        .sheet(isPresented: $showEarningsSheet) {
            MeEarnings068(theme: palette)
                .eusoSheetX()
        }
    }

    private func refreshAll() async {
        // Fire both in parallel — neither depends on the other.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await loadsStore.refresh() }
            group.addTask { await earningsStore.refresh() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WEEKLY PLAN")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Text(weekRangeLabel())
                    .font(EType.h2)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            if case .loaded(let items) = loadsStore.state, !items.isEmpty {
                Text("\(items.count)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(palette.textPrimary)
                Text(items.count == 1 ? "LOAD" : "LOADS")
                    .font(EType.micro)
                    .tracking(1.2)
                    .foregroundColor(palette.textTertiary)
            }
        }
    }

    // MARK: - Bucket picker

    private var bucketPicker: some View {
        HStack(spacing: 0) {
            ForEach(MyLoadsStore.Bucket.allCases) { b in
                bucketChip(b)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Radius.pill)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func bucketChip(_ b: MyLoadsStore.Bucket) -> some View {
        let selected = bucket == b
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                bucket = b
            }
        } label: {
            Text(b.displayLabel)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(
                    selected
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(palette.textSecondary)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s2)
                .background(
                    Group {
                        if selected {
                            Capsule().fill(LinearGradient.diagonal)
                        } else {
                            Capsule().fill(Color.clear)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(b.displayLabel) loads")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Loads section

    @ViewBuilder
    private var loadsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(bucket.sectionHeader)
                .font(EType.micro)
                .tracking(1.4)
                .foregroundColor(palette.textSecondary)

            switch loadsStore.state {
            case .loading:
                loadsLoadingPane
            case .empty:
                loadsEmptyPane
            case .error(let err):
                loadsErrorPane(err: err)
            case .loaded(let items):
                loadsList(items: items)
            }
        }
    }

    private var loadsLoadingPane: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Loading your \(bucket.rawValue) roster…")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private var loadsEmptyPane: some View {
        EusoEmptyState(
            systemImage: bucket.emptyGlyph,
            title: bucket.emptyTitle,
            subtitle: bucket.emptySubtitle,
            cta: (label: "Refresh", action: {
                Task { await loadsStore.refresh() }
            })
        )
    }

    private func loadsErrorPane(err: Error) -> some View {
        EusoEmptyState(
            systemImage: "exclamationmark.triangle",
            title: "Couldn't load your roster",
            subtitle: err.localizedDescription,
            cta: (label: "Retry", action: {
                Task { await loadsStore.refresh() }
            })
        )
    }

    @ViewBuilder
    private func loadsList(items: [LoadSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { (idx, l) in
                loadRow(l)
                if idx < items.count - 1 {
                    Divider().background(palette.borderFaint)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func loadRow(_ l: LoadSummary) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(l.loadNumber)
                        .font(EType.bodyStrong.monospacedDigit())
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    loadStatusPill(status: l.status)
                }
                Text(routeLine(origin: l.origin, destination: l.destination))
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
                if let cargo = l.cargoType, !cargo.isEmpty {
                    Text(cargo.uppercased())
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundColor(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s3)
            VStack(alignment: .trailing, spacing: 4) {
                Text(currencyShort(l.rate))
                    .font(EType.bodyStrong.monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                Text(pickupShort(l.pickupDate))
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundColor(palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s4)
        .contentShape(Rectangle())
    }

    // MARK: - Earnings section (mini 7-week bar chart)

    @ViewBuilder
    private var earningsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("LAST 7 WEEKS")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                if case .loaded(let bars) = earningsStore.state {
                    Text(currencyShort(totalEarnings(bars: bars)))
                        .font(EType.bodyStrong.monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                }
            }
            earningsBody
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var earningsBody: some View {
        switch earningsStore.state {
        case .loading:
            HStack(spacing: Space.s3) {
                ProgressView()
                Text("Loading your last 7 weeks…")
                    .font(EType.caption)
                    .foregroundColor(palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Space.s3)
        case .empty:
            Text("Your weekly earnings show up here once your first settlement clears.")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        case .error(let err):
            Text("Weekly earnings unavailable — \(err.localizedDescription)")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded(let bars):
            weeklyChart(bars: bars)
        }
    }

    /// 7-bar gradient chart. The server returns rows newest-first; we
    /// reverse so the chart reads left-to-right (oldest → this week).
    private func weeklyChart(bars: [WeeklyEarningsBar]) -> some View {
        let ordered = Array(bars.reversed())
        let maxEarnings = max(ordered.map(\.totalEarnings).max() ?? 0, 1)
        return GeometryReader { geo in
            let spacing: CGFloat = Space.s2
            let barCount = CGFloat(ordered.count)
            let totalSpacing = spacing * max(barCount - 1, 0)
            let barWidth = max((geo.size.width - totalSpacing) / max(barCount, 1), 0)
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(ordered) { row in
                    let ratio = CGFloat(row.totalEarnings / maxEarnings)
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(
                                row.totalEarnings > 0
                                ? AnyShapeStyle(LinearGradient.diagonal)
                                : AnyShapeStyle(palette.borderFaint)
                            )
                            .frame(
                                width: barWidth,
                                height: max(ratio * (geo.size.height - 16), 4)
                            )
                        Text(weekShortLabel(start: row.weekStart))
                            .font(EType.micro)
                            .tracking(0.8)
                            .foregroundColor(palette.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 120)
    }

    // MARK: - Action rows

    private var actionRows: some View {
        VStack(spacing: 0) {
            actionRow(
                systemImage: "arrow.clockwise",
                title: "Refresh weekly plan",
                subtitle: "Pulls the latest roster + earnings"
            ) {
                Task { await refreshAll() }
            }
            Divider().background(palette.borderFaint)
            actionRow(
                systemImage: "chart.bar.xaxis",
                title: "View full earnings breakdown",
                subtitle: "Period splits, top loads, tax summary",
                disabled: !hasAnyEarnings
            ) {
                showEarningsSheet = true
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func actionRow(
        systemImage: String,
        title: String,
        subtitle: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        disabled
                        ? AnyShapeStyle(palette.textTertiary)
                        : AnyShapeStyle(LinearGradient.diagonal)
                    )
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundColor(
                            disabled ? palette.textTertiary : palette.textPrimary
                        )
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundColor(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.textTertiary)
            }
            .padding(Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Derived state

    private var hasAnyEarnings: Bool {
        if case .loaded(let bars) = earningsStore.state,
           bars.contains(where: { $0.totalEarnings > 0 }) {
            return true
        }
        return false
    }

    // MARK: - Load row helpers

    private func loadStatusPill(status: String) -> some View {
        let color = loadStatusColor(status: status)
        return Text(status.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(EType.micro)
            .tracking(1.0)
            .foregroundColor(color)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }

    private func loadStatusColor(status: String) -> Color {
        switch status.lowercased() {
        case "in_transit", "assigned":            return palette.success
        case "at_pickup", "at_delivery":           return palette.warning
        case "pending":                            return palette.textSecondary
        case "completed":                          return palette.success
        case "cancelled", "disputed":              return palette.danger
        default:                                   return palette.textTertiary
        }
    }

    private func routeLine(origin: String, destination: String) -> String {
        let o = origin.trimmingCharacters(in: .whitespaces)
        let d = destination.trimmingCharacters(in: .whitespaces)
        if o.isEmpty && d.isEmpty { return "—" }
        if o.isEmpty { return "→ \(d)" }
        if d.isEmpty { return "\(o) →" }
        return "\(o) → \(d)"
    }

    // MARK: - Format helpers

    private func currencyShort(_ amount: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: amount)) ?? "$0"
    }

    private func pickupShort(_ iso: String) -> String {
        // pickupDate arrives as ISO-8601 from the server. We render a
        // local short date only; if the string doesn't parse we fall
        // through to the original string so no render breaks.
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]
        if let d = isoFmt.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: d).uppercased()
        }
        let isoFmt2 = ISO8601DateFormatter()
        isoFmt2.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let d = isoFmt2.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: d).uppercased()
        }
        return iso
    }

    private func weekShortLabel(start: String) -> String {
        // weekStart arrives as `YYYY-MM-DD` from earnings router.
        let parts = start.split(separator: "-")
        guard parts.count >= 3 else { return "—" }
        let month = String(parts[1])
        let day = String(parts[2])
        return "\(month.trimmingPrefix("0"))/\(day.trimmingPrefix("0"))"
    }

    private func totalEarnings(bars: [WeeklyEarningsBar]) -> Double {
        bars.reduce(into: 0.0) { $0 += $1.totalEarnings }
    }

    private func weekRangeLabel() -> String {
        // Local derivation — no server call required. Uses
        // `Calendar.current` to find this week's Monday → Sunday.
        let cal = Calendar(identifier: .iso8601)
        let now = Date()
        let comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        guard let monday = cal.date(from: comp),
              let sunday = cal.date(byAdding: .day, value: 6, to: monday) else {
            return "THIS WEEK"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let startLabel = fmt.string(from: monday).uppercased()
        let endLabel = fmt.string(from: sunday).uppercased()
        return "\(startLabel) – \(endLabel)"
    }
}

// MARK: - MyLoadsStore.Bucket cosmetic metadata
//
// File-local extensions that keep the `Bucket` enum's wire shape
// untouched (the enum still maps to the canonical `loads.search` filter
// values) while attaching the copy the plan screen renders.
extension MyLoadsStore.Bucket {
    var displayLabel: String {
        switch self {
        case .active:   return "ACTIVE"
        case .pending:  return "PENDING"
        case .finished: return "FINISHED"
        }
    }

    var sectionHeader: String {
        switch self {
        case .active:   return "ACTIVE LOADS"
        case .pending:  return "PENDING OFFERS"
        case .finished: return "COMPLETED LOADS"
        }
    }

    var emptyGlyph: String {
        switch self {
        case .active:   return "truck.box"
        case .pending:  return "clock.badge.questionmark"
        case .finished: return "checkmark.seal"
        }
    }

    var emptyTitle: String {
        switch self {
        case .active:   return "No active loads"
        case .pending:  return "No pending offers"
        case .finished: return "No completed loads yet"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .active:
            return "When dispatch pairs you with a load, it shows up here with the route, rate, and pickup time."
        case .pending:
            return "Offers tendered to you but not yet accepted show up here."
        case .finished:
            return "Once a load is marked delivered, it moves here with final pay and miles."
        }
    }
}

// MARK: - Screen wrapper

struct DriverWeeklyPlanScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            DriverWeeklyPlan()
        } nav: {
            BottomNav(
                leading: driverNavLeading_058(),
                trailing: driverNavTrailing_058(),
                orbState: .idle
            )
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/058 Credentials Detail.png`
// pins ME current — Credentials Detail is a Me-ring surface (DQ
// file / docs / permits per [Driver E2E map] Ring 1 Me). iOS file
// is named `058_DriverWeeklyPlan.swift` (older slot name) but the
// shipped UI is the credentials detail. Prior iOS shipped TRIPS
// current — drifted from the Me-ring doctrine. Restored canonical:
// Home / Trips · Wallet / Me with **ME current**. Trailing
// `wallet.pass` -> canonical `creditcard` icon.
private func driverNavLeading_058() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: false)]
}

private func driverNavTrailing_058() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: true)]
}

// MARK: - Previews
//
// The live-store path is the production path. Previews render that same
// path with no authenticated session — both stores resolve to `.empty`
// deterministically without hitting the network. The screen surfaces
// the branded empty roster state + the empty-chart caption exactly the
// way a freshly-provisioned driver would see it before their first
// settlement. No fixture data is injected.

#Preview("058 · Driver Weekly Plan · Night · Empty / Live stores") {
    DriverWeeklyPlanScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("058 · Driver Weekly Plan · Afternoon · Empty / Live stores") {
    DriverWeeklyPlanScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
