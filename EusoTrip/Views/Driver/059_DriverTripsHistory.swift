//
//  059_DriverTripsHistory.swift
//  EusoTrip 2027 UI — Wave 7 (driver · trips history)
//
//  Screen 059 · Driver Trips History — retrospective view of the
//  driver's completed trips. Pulls `loads.search(status: "completed",
//  limit: 30)` through `MyLoadsStore` (pre-existing store declared at
//  ViewModels/LiveDataStores.swift L66) and renders the result with a
//  small header summary (total trips, aggregate revenue) plus a
//  reverse-chronological list of completed loads.
//
//  Cohort B — fully dynamic from day 1
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data"):
//
//    • Every row — loadNumber, origin, destination, cargoType, rate,
//      pickupDate — is rendered from the `LoadSummary` the server
//      returns on `loads.search`. No hardcoded trip numbers, no seed
//      Walmart / Wawa / Univar strings. The branded `EusoEmptyState`
//      is what a freshly-provisioned driver with zero completed loads
//      sees; a render-time render-error surfaces the localized server
//      message in place rather than disappearing the page.
//
//    • The header stats (trip count, aggregate revenue) are derived
//      locally from the loaded array — they summarize what the server
//      already returned. There is no speculative client-side math that
//      paraphrases a value the server could return itself.
//
//    • CTAs route through the existing env surface — no dead buttons.
//      "View full earnings" presents `MeEarnings068` (the canonical
//      earnings sheet), "Refresh" hits `MyLoadsStore.refresh()` which
//      round-trips the server, "Open weekly plan" presents
//      `DriverWeeklyPlan` so the driver can pivot from history →
//      current week. There are no `.onTapGesture { }` placeholders.
//
//  Doctrine refs:
//    §2   Gradient brand accents — kicker, header gradient currency
//         total, action row icons, and empty-state CTA all use
//         `LinearGradient.diagonal`. No flat `Brand.info` / `Brand.blue`
//         fills anywhere.
//    §3   Every ternary shape-style expression is wrapped in
//         `AnyShapeStyle(…)` so SwiftUI's type checker compiles cleanly
//         on iOS 17.
//    §4   Tokenized spacing (`Space.sN`), tokenized radii
//         (`Radius.sm/md/lg/pill`), tokenized type (`EType.*`).
//    §5   Palette semantic — `palette.textPrimary/Secondary/Tertiary`,
//         `palette.bgCard/bgPage`, `palette.borderFaint`. Never
//         `Color.white` / `Color.gray` / `Color.black`.
//    §9   No dead buttons — every Button has a real production action
//         and "View full earnings" is disabled while no trips are
//         loaded so we never route into a downstream screen that will
//         only show the empty state.
//    §10  Previews compile in isolation. The live-store path is the
//         production path; previews instantiate it with an
//         unauthenticated `EusoTripSession()` so both previews resolve
//         deterministically to `.empty` without the network.
//
//  Not in scope (follow-up firings):
//    • Per-trip drill-in (would require `loads.getById` + a
//      LoadDetailSheet adaptor keyed off the completed-row id).
//    • Timeframe picker (last 30 / 90 / YTD / all). The backend's
//      `loads.search` does not accept a date-range today; adding it
//      would need a small server-side extension. Current surface
//      renders whatever the backend returns under a hardcoded `limit:
//      30` — server ordering (newest-first) is preserved.
//    • CSV export — routes through `documentManagement.*`, a follow-up.
//

import SwiftUI

// MARK: - Screen

struct DriverTripsHistory: View {
    @Environment(\.palette) var palette

    @EnvironmentObject private var session: EusoTripSession

    // MARK: Live store — pre-existing, declared at LiveDataStores.swift:66.
    @StateObject private var loadsStore = MyLoadsStore()

    // MARK: Local UI state

    /// Presents the canonical MeEarnings068 sheet. Routes through the
    /// existing earnings surface — no duplicate earnings math.
    @State private var showEarningsSheet = false

    /// Presents the DriverWeeklyPlan sheet so the driver can pivot
    /// from completed-history → this-week's roster.
    @State private var showWeeklyPlanSheet = false

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                topBar
                statsCard
                tripsSection
                actionRows
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .refreshable {
            await loadsStore.refresh()
        }
        .task {
            // Pin the bucket to .finished — this screen is retrospective.
            // didSet on MyLoadsStore.bucket drives the first refresh so we
            // don't need a second explicit call here.
            if loadsStore.bucket != .finished {
                loadsStore.bucket = .finished
            } else {
                await loadsStore.refresh()
            }
        }
        .sheet(isPresented: $showEarningsSheet) {
            MeEarnings068(theme: palette)
                .eusoSheetX()
        }
        .sheet(isPresented: $showWeeklyPlanSheet) {
            DriverWeeklyPlanScreen(theme: palette)
                .eusoSheetX()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TRIPS HISTORY")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Text("Completed loads")
                    .font(EType.h2)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            if case .loaded(let items) = loadsStore.state, !items.isEmpty {
                Text("\(items.count)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(palette.textPrimary)
                Text(items.count == 1 ? "TRIP" : "TRIPS")
                    .font(EType.micro)
                    .tracking(1.2)
                    .foregroundColor(palette.textTertiary)
            }
        }
    }

    // MARK: - Stats card (derived from loaded array)

    @ViewBuilder
    private var statsCard: some View {
        switch loadsStore.state {
        case .loaded(let items) where !items.isEmpty:
            HStack(alignment: .top, spacing: Space.s4) {
                statTile(
                    kicker: "TOTAL REVENUE",
                    value: currencyShort(aggregateRevenue(items)),
                    gradient: true
                )
                Divider()
                    .frame(height: 40)
                    .overlay(palette.borderFaint)
                statTile(
                    kicker: "AVERAGE / TRIP",
                    value: currencyShort(averageRevenue(items)),
                    gradient: false
                )
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
        default:
            EmptyView()
        }
    }

    private func statTile(kicker: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundColor(palette.textTertiary)
            Text(value)
                .font(EType.h2.monospacedDigit())
                .foregroundStyle(
                    gradient
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.textPrimary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Trips section

    @ViewBuilder
    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("COMPLETED LOADS")
                .font(EType.micro)
                .tracking(1.4)
                .foregroundColor(palette.textSecondary)

            switch loadsStore.state {
            case .loading:
                loadingPane
            case .empty:
                emptyPane
            case .error(let err):
                errorPane(err: err)
            case .loaded(let items):
                if items.isEmpty {
                    emptyPane
                } else {
                    tripsList(items: items)
                }
            }
        }
    }

    private var loadingPane: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Loading your completed trips…")
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

    private var emptyPane: some View {
        EusoEmptyState(
            systemImage: "checkmark.seal",
            title: "No completed trips yet",
            subtitle: "Once a load is marked delivered, it moves here with final pay, miles, and cargo.",
            cta: (label: "Refresh", action: {
                Task { await loadsStore.refresh() }
            })
        )
    }

    private func errorPane(err: Error) -> some View {
        EusoEmptyState(
            systemImage: "exclamationmark.triangle",
            title: "Couldn't load trip history",
            subtitle: err.localizedDescription,
            cta: (label: "Retry", action: {
                Task { await loadsStore.refresh() }
            })
        )
    }

    @ViewBuilder
    private func tripsList(items: [LoadSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { (idx, l) in
                tripRow(l)
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

    private func tripRow(_ l: LoadSummary) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(l.loadNumber)
                        .font(EType.bodyStrong.monospacedDigit())
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    tripStatusPill(status: l.status)
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

    private func tripStatusPill(status: String) -> some View {
        let color = statusColor(status: status)
        return Text(status.replacingOccurrences(of: "_", with: " ").uppercased())
            .font(EType.micro)
            .tracking(1.0)
            .foregroundColor(color)
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }

    private func statusColor(status: String) -> Color {
        // The bucket is pinned to `.finished` so the server almost
        // always returns `completed`. A `disputed` or `cancelled`
        // completed-bucket row is surfaced with the canonical danger
        // color; an unexpected status falls through to tertiary so we
        // never render a missing server label as green success.
        switch status.lowercased() {
        case "completed":                  return palette.success
        case "disputed", "cancelled":      return palette.danger
        case "pending":                    return palette.warning
        default:                           return palette.textTertiary
        }
    }

    // MARK: - Action rows

    private var actionRows: some View {
        VStack(spacing: 0) {
            actionRow(
                systemImage: "arrow.clockwise",
                title: "Refresh trip history",
                subtitle: "Pulls the latest completed loads from dispatch"
            ) {
                Task { await loadsStore.refresh() }
            }
            Divider().background(palette.borderFaint)
            actionRow(
                systemImage: "calendar.badge.clock",
                title: "Open weekly plan",
                subtitle: "This week's roster + recent earnings",
                disabled: false
            ) {
                showWeeklyPlanSheet = true
            }
            Divider().background(palette.borderFaint)
            actionRow(
                systemImage: "chart.bar.xaxis",
                title: "View full earnings breakdown",
                subtitle: "Period splits, top loads, tax summary",
                disabled: !hasAnyTrips
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

    // MARK: - Derived

    private var hasAnyTrips: Bool {
        if case .loaded(let items) = loadsStore.state, !items.isEmpty {
            return true
        }
        return false
    }

    private func aggregateRevenue(_ items: [LoadSummary]) -> Double {
        items.reduce(into: 0.0) { $0 += $1.rate }
    }

    private func averageRevenue(_ items: [LoadSummary]) -> Double {
        guard !items.isEmpty else { return 0 }
        return aggregateRevenue(items) / Double(items.count)
    }

    // MARK: - Format helpers

    private func routeLine(origin: String, destination: String) -> String {
        let o = origin.trimmingCharacters(in: .whitespaces)
        let d = destination.trimmingCharacters(in: .whitespaces)
        if o.isEmpty && d.isEmpty { return "—" }
        if o.isEmpty { return "→ \(d)" }
        if d.isEmpty { return "\(o) →" }
        return "\(o) → \(d)"
    }

    private func currencyShort(_ amount: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = "USD"
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: amount)) ?? "$0"
    }

    private func pickupShort(_ iso: String) -> String {
        // Defensive ISO-8601 parse. Falls through to the server string
        // when neither internet-date nor fractional-seconds formats
        // match — we never invent a date the server didn't send.
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
}

// MARK: - Screen wrapper

struct DriverTripsHistoryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            DriverTripsHistory()
        } nav: {
            BottomNav(
                leading: driverNavLeading_059(),
                trailing: driverNavTrailing_059(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_059() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",     isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box", isCurrent: true)]
}
private func driverNavTrailing_059() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Previews
//
// Both previews render the production path — live store, no fixtures.
// An unauthenticated `EusoTripSession()` resolves the store to `.empty`
// deterministically without hitting the network, so the branded empty
// state is what shows. A real signed-in driver with completed trips
// will see the live list on device.

#Preview("059 · Driver Trips History · Night · Empty / Live store") {
    DriverTripsHistoryScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("059 · Driver Trips History · Afternoon · Empty / Live store") {
    DriverTripsHistoryScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
