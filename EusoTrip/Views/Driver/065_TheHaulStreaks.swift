//
//  065_TheHaulStreaks.swift
//  EusoTrip 2027 UI — Wave 7 (driver · The Haul · streak tracker)
//
//  Screen 065 · The Haul · Streaks — the dedicated streak surface that
//  sits alongside 060 Dashboard, 061 Missions, 062 Badges, 063 Crates,
//  and 064 Leaderboard. Drivers build streaks by completing at least
//  one load per day (the server reconciles the window from
//  `lastActivityAt`); extended streaks roll into an XP multiplier tier
//  (×1.0 → ×2.5) plus a daily bonus XP drip.
//
//  Cohort B — fully dynamic from day 1
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data"):
//
//    • Every rendered number (daily streak, weekly streak, best
//      daily, best weekly, current multiplier, next milestone, the
//      7-day history row, daily bonus XP) comes from the live tRPC
//      surface `advancedGamification.getStreakTracker` (MCP-verified
//      at frontend/server/routers/advancedGamification.ts:1476).
//      `StreakTrackerStore` in `ViewModels/LiveDataStores.swift` owns
//      the fetch.
//
//    • Multiplier tiers are echoed from the server, never computed
//      locally. The progress bar between "current multiplier" and
//      "next multiplier" reads straight off the envelope fields
//      (currentMultiplier, nextMultiplierAt, nextMultiplierValue).
//
//    • The 7-day history rail renders exactly the rows the server
//      returned — if the server sent five `completed: false` days we
//      render five open dots; we never pad or fabricate.
//
//    • Empty-streak hero is keyed off `dailyStreak == 0 &&
//      bestDailyStreak == 0` (a brand-new driver), not off a `.empty`
//      store state — the server always returns a populated envelope.
//
//    • Zero CTAs without a destination. "How streaks work" is a
//      read-only concept card; no dead buttons.
//
//  Doctrine refs:
//    §2 Gradient-only brand accents — streak numeral, multiplier ring,
//       progress bar fill, completed history dot, and "How it works"
//       bullet leaders all render `LinearGradient.diagonal`. Every
//       ternary shape-style wraps in `AnyShapeStyle(...)` per §9.
//    §3 Numbers-first — the daily streak numeral and current
//       multiplier dominate the visual hierarchy above any chrome.
//    §4 Tokenized spacing (`Space.sN`), radii (`Radius.sm/md/lg/xl`),
//       and type (`EType.*`). No magic numbers.
//    §5 Palette semantic — `palette.textPrimary/Secondary/Tertiary`,
//       `palette.bgCard`, `palette.borderFaint`, `palette.tintNeutral`.
//       No hard-coded Color literals.
//    §7 Previews in both registers.
//    §10 Previews compile in isolation — the store stays in `.loading`
//       so both registers render the skeleton without network.
//

import SwiftUI

// MARK: - Screen

struct TheHaulStreaks: View {
    @Environment(\.palette) var palette
    @StateObject private var store = StreakTrackerStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    loadingSkeleton
                case .empty:
                    // Server always returns a populated envelope for an
                    // authenticated driver; `.empty` here only fires if
                    // the decoder sees zero fields, which indicates a
                    // schema drift rather than a cold-start driver.
                    schemaDriftBanner
                case .error(let err):
                    errorBanner(err)
                case .loaded(let tracker):
                    if tracker.dailyStreak == 0 && tracker.bestDailyStreak == 0 {
                        coldStartHero
                    } else {
                        streakHero(tracker)
                        multiplierCard(tracker)
                        historyCard(tracker)
                        statsRow(tracker)
                    }
                }
                conceptCard
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Streaks")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Daily rhythm · multiplier · 7-day window")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States — loading / empty / error / cold-start

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s3) {
            ProgressView()
                .tint(palette.textSecondary)
            Text("Checking your streak…")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
    }

    private var schemaDriftBanner: some View {
        EusoEmptyState(
            systemImage: "exclamationmark.bubble",
            title: "Streak data unavailable",
            subtitle: "We couldn't read your streak tracker from the server. Pull to refresh.",
            comingSoon: false
        )
    }

    private var coldStartHero: some View {
        EusoEmptyState(
            systemImage: "flame",
            title: "Start a streak today",
            subtitle: "Complete one load per day to build your streak. Your first day unlocks a ×1.2 multiplier at day 3."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't reach the streak tracker")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(
                        Capsule().fill(LinearGradient.diagonal)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Hero — current streak numeral + multiplier chip

    private func streakHero(_ tracker: AdvancedGamificationAPI.StreakTracker) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CURRENT STREAK")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("×\(formatMultiplier(tracker.currentMultiplier))")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(LinearGradient.diagonal)
                    )
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("\(tracker.dailyStreak)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.dailyStreak == 1 ? "day" : "days")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("+\(tracker.dailyBonusXp) XP today")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Multiplier card — progress toward next milestone

    private func multiplierCard(_ tracker: AdvancedGamificationAPI.StreakTracker) -> some View {
        let current = tracker.currentMultiplier
        let target = tracker.nextMultiplierValue
        let atDays = tracker.nextMultiplierAt
        // Fraction of the way from current milestone to next. Server
        // doesn't echo the floor of the current milestone, so we
        // approximate by using dailyStreak / nextMultiplierAt when
        // nextMultiplierAt > 0. If already at the top tier (target ==
        // current), we render a full bar.
        let progress: Double = {
            if target <= current { return 1.0 }
            guard atDays > 0 else { return 0.0 }
            let ratio = Double(tracker.dailyStreak) / Double(atDays)
            return min(max(ratio, 0.0), 1.0)
        }()

        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("MULTIPLIER")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("×\(formatMultiplier(current))")
                    .font(EType.h1)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if target > current {
                    Text("next ×\(formatMultiplier(target)) at \(atDays) days")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Text("max tier")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.tintNeutral)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .frame(width: max(0, geo.size.width * CGFloat(progress)), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: History — 7-day rail

    private func historyCard(_ tracker: AdvancedGamificationAPI.StreakTracker) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("LAST 7 DAYS")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }

            HStack(spacing: Space.s2) {
                ForEach(tracker.streakHistory) { day in
                    VStack(spacing: Space.s1) {
                        Text(dayLabel(for: day.date))
                            .font(EType.micro)
                            .tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        ZStack {
                            Circle()
                                .fill(
                                    day.completed
                                    ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.tintNeutral)
                                )
                                .frame(width: 28, height: 28)
                            if day.completed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    day.completed
                                    ? AnyShapeStyle(Color.clear)
                                    : AnyShapeStyle(palette.borderFaint),
                                    lineWidth: 1
                                )
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Stats row — secondary numbers

    private func statsRow(_ tracker: AdvancedGamificationAPI.StreakTracker) -> some View {
        HStack(spacing: Space.s3) {
            statTile(label: "WEEKLY", value: "\(tracker.weeklyStreak)")
            statTile(label: "BEST DAILY", value: "\(tracker.bestDailyStreak)")
            statTile(label: "BEST WEEKLY", value: "\(tracker.bestWeeklyStreak)")
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Concept card — evergreen product documentation

    private var conceptCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("HOW STREAKS WORK")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
            }

            Text("Drive one load per day to keep your streak alive.")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.s2) {
                conceptBullet(
                    systemImage: "flame",
                    text: "Every active day adds to your daily streak. Miss a day, the streak resets — the server reconciles against your last load."
                )
                conceptBullet(
                    systemImage: "bolt",
                    text: "Streaks unlock XP multipliers: day 3 → ×1.2, day 7 → ×1.4, day 14 → ×1.6, day 30 → ×1.8, day 60 → ×2.0, day 90 → ×2.5."
                )
                conceptBullet(
                    systemImage: "plus.circle",
                    text: "Daily bonus XP scales with streak length. The longer you go, the more each completed load is worth."
                )
            }
            .padding(.top, Space.s1)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func conceptBullet(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 18)
                .padding(.top, 2)
            Text(text)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    /// Format the multiplier as "1.0", "1.2", "2.5" — trailing zero
    /// trimmed for whole numbers so "×2" reads cleaner than "×2.0"
    /// when the server gives us an integer.
    private func formatMultiplier(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    /// Reduce an ISO yyyy-MM-dd date string to a 3-letter weekday
    /// abbreviation ("Mon", "Tue", …) for the history rail. Falls back
    /// to the raw date if parsing fails — we never fabricate a day.
    private func dayLabel(for iso: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "EEE"
        return out.string(from: date).uppercased()
    }
}

// MARK: - Screen wrapper

struct TheHaulStreaksScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TheHaulStreaks()
        } nav: {
            BottomNav(
                leading: driverNavLeading_065(),
                trailing: driverNavTrailing_065(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_065() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: true)]
}
private func driverNavTrailing_065() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Previews
//
// Previews never run the `.task` refresh — the store stays in `.loading`
// so both registers render the loading skeleton without hitting the
// network. No fixtures.

#Preview("065 · The Haul Streaks · Night") {
    TheHaulStreaksScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("065 · The Haul Streaks · Afternoon") {
    TheHaulStreaksScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
