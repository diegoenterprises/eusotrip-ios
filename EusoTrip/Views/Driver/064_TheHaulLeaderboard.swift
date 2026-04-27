//
//  064_TheHaulLeaderboard.swift
//  EusoTrip 2027 UI — Wave 7 (driver · The Haul · leaderboard)
//
//  Screen 064 · The Haul · Leaderboard — the dedicated fleet-ranking
//  surface reached from Me → Haul or from the 060 dashboard's "Open
//  leaderboard" action row. The Me sub-route `MeHaulView` renders a
//  thumbnail version; this brick is the full-bleed detail surface.
//
//  Cohort B — fully dynamic from day 1
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data"):
//
//    • Every rendered number (your rank, total participants, top-N
//      list, percentile, each leader's level / XP / name) comes from
//      the live tRPC surface `gamification.getLeaderboard`
//      (MCP-verified at frontend/server/routers/gamification.ts:294).
//      The new `LeaderboardSnapshotStore` (LiveDataStores.swift)
//      preserves the full envelope — rows + myRank + totalParticipants
//      — so the self-rank hero never fabricates "#?" and the
//      participant denominator is always the server's real count.
//
//    • Period / category / role filters re-query the server; no local
//      resorting of stale rows. Every segmented-control change calls
//      `store.refresh()` with the new parameters — if the server
//      returns an empty list for that cut, the branded `EusoEmptyState`
//      primitive renders. There are no sample leaders on disk, no
//      fallback tier names, no fabricated rank deltas.
//
//    • Zero CTAs without a sheet / navigation target. "Refresh"
//      re-queries; tapping a leader row in a future iteration will
//      open their public profile (backend router not yet live — row
//      is flat for now, no dead button).
//
//  Doctrine refs:
//    §2 Gradient-only brand accents — your-rank hero numeral, filter
//       chip selection state, and the "you" row highlight all render
//       `LinearGradient.diagonal`. Every ternary shape-style wraps in
//       `AnyShapeStyle(...)` per §9.
//    §3 Numbers-first — rank / participant denominator / top-5 list
//       dominate the visual hierarchy above any chrome.
//    §4 Tokenized spacing (`Space.sN`), radii (`Radius.sm/md/lg/xl`),
//       and type (`EType.*`). No magic numbers.
//    §5 Palette semantic — `palette.textPrimary/Secondary/Tertiary`,
//       `palette.bgCard`, `palette.borderFaint`, `palette.tintNeutral`.
//       No hard-coded Color literals.
//    §7 Previews in both registers.
//    §10 Previews compile in isolation — the store surfaces `.empty`
//       /`.error` deterministically when offline so both previews
//       render the branded empty path without hitting the network.
//
//  Not in scope (follow-up firings):
//    • Leader row tap → public driver profile (backend router TBD)
//    • Historical trend chart (requires `getLeaderboardHistory`)
//    • Guild / vertical team leaderboards (requires the guild router)
//

import SwiftUI

// MARK: - Screen

struct TheHaulLeaderboard: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    @StateObject private var store = LeaderboardSnapshotStore()

    // MARK: UI state — each selection re-queries the server.
    @State private var selectedPeriod: LeaderboardPeriod = .month
    @State private var selectedCategory: LeaderboardCategory = .points

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                periodFilter
                categoryFilter
                heroCard
                leadersCard
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        store.period = selectedPeriod.apiValue
        store.category = selectedCategory.apiValue
        // `roleFilter: "own"` asks the server for the caller's own
        // role pool (drivers vs drivers). Leaving that hard-coded for
        // now; a third filter segment is a follow-up brick once role
        // scoping is surfaced in the Me hub settings.
        store.roleFilter = "own"
        await store.refresh()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(palette.bgCard)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("THE HAUL")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Text("Leaderboard")
                    .font(EType.h2)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
        }
    }

    // MARK: - Filters

    private var periodFilter: some View {
        filterStrip(
            title: "PERIOD",
            options: LeaderboardPeriod.allCases,
            selection: Binding(
                get: { selectedPeriod },
                set: { newValue in
                    guard newValue != selectedPeriod else { return }
                    selectedPeriod = newValue
                    Task { await refresh() }
                }
            ),
            label: { $0.display }
        )
    }

    private var categoryFilter: some View {
        filterStrip(
            title: "CATEGORY",
            options: LeaderboardCategory.allCases,
            selection: Binding(
                get: { selectedCategory },
                set: { newValue in
                    guard newValue != selectedCategory else { return }
                    selectedCategory = newValue
                    Task { await refresh() }
                }
            ),
            label: { $0.display }
        )
    }

    private func filterStrip<Option: Hashable>(
        title: String,
        options: [Option],
        selection: Binding<Option>,
        label: @escaping (Option) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundColor(palette.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                        let isSelected = opt == selection.wrappedValue
                        Button {
                            selection.wrappedValue = opt
                        } label: {
                            Text(label(opt))
                                .font(EType.caption)
                                .tracking(0.6)
                                .foregroundColor(
                                    isSelected ? palette.textPrimary : palette.textSecondary
                                )
                                .padding(.horizontal, Space.s3)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            isSelected
                                            ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.16))
                                            : AnyShapeStyle(palette.bgCard)
                                        )
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected
                                            ? AnyShapeStyle(LinearGradient.diagonal)
                                            : AnyShapeStyle(palette.borderFaint),
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Self-rank hero

    @ViewBuilder
    private var heroCard: some View {
        switch store.state {
        case .loading:
            loadingCard(title: "Computing your rank…")
        case .empty:
            EusoEmptyState(
                systemImage: "trophy",
                title: "No leaderboard rows yet",
                subtitle: "Once drivers start posting \(selectedCategory.dataNoun) this \(selectedPeriod.display.lowercased()), your rank will appear here.",
                cta: (label: "Refresh", action: {
                    Task { await refresh() }
                })
            )
        case .error(let err):
            errorCard(err: err) {
                Task { await refresh() }
            }
        case .loaded(let snap):
            heroCardLoaded(snapshot: snap)
        }
    }

    private func heroCardLoaded(snapshot: GamificationAPI.LeaderboardSnapshot) -> some View {
        let pct = percentile(myRank: snapshot.myRank,
                             totalParticipants: snapshot.totalParticipants)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("YOUR RANK")
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Text(selectedPeriod.display.uppercased())
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundColor(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("#\(snapshot.myRank)")
                    .font(EType.h1.monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if snapshot.totalParticipants > 0 {
                    Text("/ \(numberCompact(snapshot.totalParticipants))")
                        .font(EType.caption.monospacedDigit())
                        .foregroundColor(palette.textTertiary)
                }
                Spacer()
                if let pct = pct {
                    Text("Top \(pct)%")
                        .font(EType.caption.monospacedDigit())
                        .foregroundColor(palette.textSecondary)
                }
            }
            Text("Across \(numberCompact(snapshot.totalParticipants)) \(snapshot.role == "driver" ? "drivers" : "participants") in \(selectedCategory.dataNoun)")
                .font(EType.caption)
                .foregroundColor(palette.textSecondary)
                .lineLimit(2)
        }
        .padding(Space.s5)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    /// Percentile derived from rank + total. Returns `nil` when either
    /// side is absent / non-positive — so the row simply skips rendering
    /// rather than printing "Top 100%" or "Top 0%".
    private func percentile(myRank: Int, totalParticipants: Int) -> Int? {
        guard myRank > 0, totalParticipants > 0 else { return nil }
        let p = Double(myRank) / Double(totalParticipants)
        let clamped = min(1.0, max(0.0, p))
        // Always at least 1 to avoid the degenerate "Top 0%" edge.
        return max(1, Int(round(clamped * 100)))
    }

    // MARK: - Leaders list

    @ViewBuilder
    private var leadersCard: some View {
        switch store.state {
        case .loading:
            // Hero already shows loading; don't double-render.
            EmptyView()
        case .empty, .error:
            // Hero already shows empty/error state.
            EmptyView()
        case .loaded(let snap):
            if snap.rows.isEmpty {
                EusoEmptyState(
                    systemImage: "person.3",
                    title: "No leaders yet",
                    subtitle: "Nobody has posted \(selectedCategory.dataNoun) in this \(selectedPeriod.display.lowercased()).",
                    cta: (label: "Refresh", action: {
                        Task { await refresh() }
                    })
                )
            } else {
                leadersList(snap: snap)
            }
        }
    }

    private func leadersList(snap: GamificationAPI.LeaderboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TOP \(numberCompact(snap.rows.count))")
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Text(selectedCategory.display.uppercased())
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundColor(palette.textTertiary)
            }
            .padding(.horizontal, Space.s2)
            VStack(spacing: 0) {
                ForEach(Array(snap.rows.enumerated()), id: \.element.id) { idx, row in
                    leaderRow(row: row)
                    if idx != snap.rows.count - 1 {
                        Divider().background(palette.borderFaint)
                            .padding(.leading, Space.s5)
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
    }

    private func leaderRow(row: LeaderboardRow) -> some View {
        HStack(spacing: Space.s3) {
            rankBadge(rank: row.rank, isCurrent: row.isCurrentDriver)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(row.displayName)
                        .font(EType.bodyStrong)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    if row.isCurrentDriver {
                        Text("YOU")
                            .font(EType.micro)
                            .tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                if let delta = row.changeVsLastWeek {
                    Text(deltaLabel(delta: delta))
                        .font(EType.caption.monospacedDigit())
                        .foregroundColor(
                            delta > 0 ? palette.textSecondary :
                            delta < 0 ? palette.textTertiary : palette.textTertiary
                        )
                } else {
                    // Server didn't include a delta for this cut — render
                    // a neutral caption instead of a fabricated arrow.
                    Text("—")
                        .font(EType.caption.monospacedDigit())
                        .foregroundColor(palette.textTertiary)
                }
            }
            Spacer()
            Text(numberCompact(row.score))
                .font(EType.bodyStrong.monospacedDigit())
                .foregroundStyle(
                    row.isCurrentDriver
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.textPrimary)
                )
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func rankBadge(rank: Int, isCurrent: Bool) -> some View {
        Text("\(rank)")
            .font(EType.bodyStrong.monospacedDigit())
            .foregroundColor(
                isCurrent ? palette.textPrimary : palette.textSecondary
            )
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(
                        isCurrent
                        ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                        : AnyShapeStyle(palette.tintNeutral)
                    )
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        isCurrent
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
            )
    }

    private func deltaLabel(delta: Int) -> String {
        if delta > 0 { return "▲ \(delta) vs last \(selectedPeriod.shortUnit)" }
        if delta < 0 { return "▼ \(abs(delta)) vs last \(selectedPeriod.shortUnit)" }
        return "— unchanged"
    }

    // MARK: - Shared loading / error helpers

    private func loadingCard(title: String) -> some View {
        HStack(spacing: Space.s3) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(palette.textSecondary)
            Text(title)
                .font(EType.body)
                .foregroundColor(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s5)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func errorCard(err: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.textSecondary)
                Text("Couldn't load leaderboard")
                    .font(EType.bodyStrong)
                    .foregroundColor(palette.textPrimary)
            }
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundColor(palette.textSecondary)
                .lineLimit(3)
            Button(action: retry) {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundColor(palette.textPrimary)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s5)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func numberCompact(_ value: Int) -> String {
        let abs = Swift.abs(value)
        let sign = value < 0 ? "-" : ""
        switch abs {
        case 0..<1_000:
            return "\(sign)\(abs)"
        case 1_000..<10_000:
            let v = Double(abs) / 1_000
            return String(format: "\(sign)%.1fK", v).replacingOccurrences(of: ".0K", with: "K")
        case 10_000..<1_000_000:
            return "\(sign)\(abs / 1_000)K"
        default:
            let v = Double(abs) / 1_000_000
            return String(format: "\(sign)%.1fM", v).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}

// MARK: - Filter enums

private enum LeaderboardPeriod: CaseIterable, Hashable {
    case week, month, season, allTime

    var apiValue: String {
        switch self {
        case .week:    return "week"
        case .month:   return "month"
        case .season:  return "season"
        case .allTime: return "all_time"
        }
    }
    var display: String {
        switch self {
        case .week:    return "This week"
        case .month:   return "This month"
        case .season:  return "This season"
        case .allTime: return "All time"
        }
    }
    var shortUnit: String {
        switch self {
        case .week:    return "week"
        case .month:   return "month"
        case .season:  return "season"
        case .allTime: return "snapshot"
        }
    }
}

private enum LeaderboardCategory: CaseIterable, Hashable {
    case points, miles, deliveries, safety

    var apiValue: String {
        switch self {
        case .points:     return "points"
        case .miles:      return "miles"
        case .deliveries: return "deliveries"
        case .safety:     return "safety"
        }
    }
    var display: String {
        switch self {
        case .points:     return "XP"
        case .miles:      return "Miles"
        case .deliveries: return "Loads"
        case .safety:     return "Safety"
        }
    }
    var dataNoun: String {
        switch self {
        case .points:     return "XP"
        case .miles:      return "miles"
        case .deliveries: return "load completions"
        case .safety:     return "safety score"
        }
    }
}

// MARK: - Screen wrapper

struct TheHaulLeaderboardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TheHaulLeaderboard()
        } nav: {
            BottomNav(
                leading: driverNavLeading_064(),
                trailing: driverNavTrailing_064(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_064() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",          isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy",         isCurrent: true)]
}
private func driverNavTrailing_064() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass",   isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",        isCurrent: false)]
}

// MARK: - Previews

#Preview("064 · The Haul Leaderboard · Night · Empty / Live store") {
    TheHaulLeaderboardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("064 · The Haul Leaderboard · Afternoon · Empty / Live store") {
    TheHaulLeaderboardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
