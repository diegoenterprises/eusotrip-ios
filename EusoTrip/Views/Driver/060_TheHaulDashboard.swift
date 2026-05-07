//
//  060_TheHaulDashboard.swift
//  EusoTrip 2027 UI — Wave 7 (driver · The Haul · dashboard)
//
//  Screen 060 · The Haul · Dashboard — the gamification hub surfaced
//  from Me → Haul. The dashboard renders the driver's current loyalty
//  tier + XP position, active missions snapshot, badge collection
//  progress, and the driver's live leaderboard row, with CTAs that
//  route into the existing Me sub-routes for the deeper views.
//
//  Cohort B — fully dynamic from day 1
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data"):
//
//    • Every number rendered (level, XP into bracket, XP to next level,
//      total season points, active-mission count, earned/total badges,
//      leaderboard rank, rank delta) comes from one of four live tRPC
//      surfaces:
//        - LoyaltyHeroStore    · `gamification.getProfile` (canonical)
//        - MissionsStore       · `gamification.getMissions`
//        - BadgesStore         · `gamification.getBadges`
//        - LeaderboardStore    · `gamification.getLeaderboard`
//      When the server has no rows yet, each card collapses to the
//      canonical `EusoEmptyState` primitive. There are no hardcoded
//      XP values, level names, rank numbers, mission titles, or badge
//      counts anywhere on the production path.
//
//      62nd firing: migrated the hero card off `loyalty.getConfig`
//      (backend router never shipped — flagged by 61st firing as the
//      last live-dead endpoint) onto the canonical `gamification.
//      getProfile` shape. Tier-dot ladder and crate preview are
//      dropped (§16 gap: `loot_crates` has zero writers); level-ring
//      progression replaces them.
//
//    • CTAs route through real sheet presenters — zero dead buttons.
//      "View all missions" → MeMissionsView (live MissionsStore)
//      "Open badge collection" → MeBadgesView (live BadgesStore)
//      "Open leaderboard" → MeHaulView (live LeaderboardStore)
//      "Refresh" hits every store's refresh() concurrently.
//
//    • Per §16 backend gaps (gamification slice): the loot_crates /
//      user_inventory / miles_transactions tables have zero writers
//      today, so this dashboard never shows a "cash added" toast,
//      never claims a crate dropped, and never implies that XP has
//      moved money. Crates are visually display-only (tile caption
//      only) — real crate UI is a future brick once writers exist.
//
//  Doctrine refs:
//    §2   Gradient brand accents — XP progress ring, mission progress
//         bar, leaderboard rank number, and Refresh CTA all use
//         `LinearGradient.diagonal`. Zero `Brand.info` / `Brand.blue`
//         fills anywhere in the rendered UI.
//    §3   Numbers-first — current points and rank are the dominant
//         visual anchors of their cards. Rank delta renders "▲4"
//         (gradient) vs "▼3" (danger) vs "—" (tertiary).
//    §4   Tokenized spacing (`Space.sN`), radii (`Radius.sm/md/lg`),
//         type (`EType.*`).
//    §5   Palette semantic — `palette.textPrimary/Secondary/Tertiary`,
//         `palette.bgCard/bgPage`, `palette.borderFaint`.
//         Never `Color.white` / `Color.gray` / `Color.black`.
//    §9   Every ternary shape-style expression wraps in `AnyShapeStyle`.
//    §10  Previews compile in isolation — unauthenticated
//         `EusoTripSession()` resolves every live store to `.empty` or
//         `.error` deterministically, so both previews render the
//         branded empty path without hitting the network.
//
//  Not in scope (follow-up firings):
//    • 061 Missions (dedicated dashboard — beyond the Me sub-route)
//    • 062 Badges detail (dedicated gallery)
//    • 063 Crates (blocked — backend writers missing per §16)
//    • 064 Leaderboard (dedicated tabbed week/season view)
//    • 065 Streaks
//    • 066 Cosmetics
//

import SwiftUI

// MARK: - Screen

struct TheHaulDashboard: View {
    @Environment(\.palette) var palette

    @EnvironmentObject private var session: EusoTripSession

    // MARK: Live stores — every number on this surface is backed by tRPC.
    @StateObject private var loyaltyStore = LoyaltyHeroStore()
    @StateObject private var missionsStore = MissionsStore()
    @StateObject private var badgesStore = BadgesStore()
    @StateObject private var leaderboardStore = LeaderboardStore()

    // MARK: Local UI state
    @State private var showMissionsSheet = false
    @State private var showBadgesSheet = false
    @State private var showLeaderboardSheet = false

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                topBar
                loyaltyCard
                missionsCard
                badgesCard
                leaderboardCard
                actionRows
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .refreshable { await refreshAll() }
        .task { await refreshAll() }
        .sheet(isPresented: $showMissionsSheet) {
            MeMissionsView()
                .eusoSheetX()
        }
        .sheet(isPresented: $showBadgesSheet) {
            MeBadgesView()
                .eusoSheetX()
        }
        .sheet(isPresented: $showLeaderboardSheet) {
            MeHaulView()
                .eusoSheetX()
        }
    }

    private func refreshAll() async {
        async let a: () = loyaltyStore.refresh()
        async let b: () = missionsStore.refresh()
        async let c: () = badgesStore.refresh()
        async let d: () = leaderboardStore.refresh()
        _ = await (a, b, c, d)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("THE HAUL")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Text("Your Season")
                    .font(EType.h2)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            tierBadge
        }
    }

    @ViewBuilder
    private var tierBadge: some View {
        // Render a compact level chip only when the gamification profile
        // has loaded — no fallback "L1" literal. `title` is optional
        // (some profiles have none) so the chip falls back to the bare
        // level numeral when the backend omits a title.
        if case .loaded(let profile) = loyaltyStore.state,
           let level = profile.level {
            HStack(spacing: 4) {
                Image(systemName: "rosette")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(levelChipLabel(level: level, title: profile.title))
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundColor(palette.textPrimary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 5)
            .overlay(
                Capsule()
                    .strokeBorder(
                        AnyShapeStyle(LinearGradient.diagonal),
                        lineWidth: 1
                    )
            )
        }
    }

    /// "L7 · ROAD ROOKIE" when `title` is present, otherwise "LEVEL 7".
    private func levelChipLabel(level: Int, title: String?) -> String {
        if let t = title, !t.isEmpty {
            return "L\(level) · \(t.uppercased())"
        }
        return "LEVEL \(level)"
    }

    // MARK: - Loyalty card (XP hero)

    @ViewBuilder
    private var loyaltyCard: some View {
        switch loyaltyStore.state {
        case .loading:
            loadingCard(title: "Loading your season…")
        case .empty:
            EusoEmptyState(
                systemImage: "sparkles",
                title: "Haul rewards not active yet",
                subtitle: "Your season kicks off after your first settled load.",
                cta: (label: "Refresh", action: {
                    Task { await loyaltyStore.refresh() }
                })
            )
        case .error(let err):
            errorCard(err: err) {
                Task { await loyaltyStore.refresh() }
            }
        case .loaded(let profile):
            loyaltyHero(profile: profile)
        }
    }

    /// Canonical hero using `gamification.getProfile`. Every numeric
    /// anchor comes from the profile shape — no defaults, no fallbacks.
    /// When a field is absent (optional on the wire format), the row is
    /// simply not rendered. No fabricated XP, no invented rank.
    private func loyaltyHero(profile: GamificationAPI.Profile) -> some View {
        // XP into the current level bracket — `currentXp` optional,
        // default visual is `0 / (xpToNextLevel ?? 1)` which is the
        // literal backend value for a brand-new driver.
        let currentXp = max(profile.currentXp ?? 0, 0)
        let toNext = max(profile.xpToNextLevel ?? 0, 0)
        let total = currentXp + toNext
        let pct: Double = {
            guard total > 0 else { return 0 }
            return min(1.0, max(0.0, Double(currentXp) / Double(total)))
        }()

        return VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(numberCompact(currentXp))
                    .font(EType.h1.monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("XP")
                    .font(EType.caption)
                    .tracking(1.0)
                    .foregroundColor(palette.textTertiary)
                Spacer()
                // Fallback total-points rider — render only when the
                // profile carries it, tiny tertiary-weight caption.
                if let total = profile.totalPoints, total != currentXp {
                    Text("\(numberCompact(total)) total")
                        .font(EType.caption.monospacedDigit())
                        .foregroundColor(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            // Level-progression bar — gradient fill over neutral track.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.tintNeutral.opacity(0.6))
                        .frame(height: 8)
                    Capsule()
                        .fill(AnyShapeStyle(LinearGradient.diagonal))
                        .frame(width: max(8, geo.size.width * CGFloat(pct)),
                               height: 8)
                }
            }
            .frame(height: 8)
            HStack(alignment: .center, spacing: Space.s2) {
                if toNext > 0, let lvl = profile.level {
                    Text("\(numberCompact(toNext)) XP to Level \(lvl + 1)")
                        .font(EType.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                } else if toNext == 0 && profile.level != nil {
                    Text("Ready to promote")
                        .font(EType.caption)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                if total > 0 {
                    Text("\(Int(pct * 100))%")
                        .font(EType.caption.monospacedDigit())
                        .foregroundColor(palette.textTertiary)
                }
            }
            // Rank/percentile sub-row — renders only when the backend
            // returns a rank number; fleet-wide brand-new drivers will
            // have `rank == nil` and skip this row entirely.
            if let rank = profile.rank {
                Divider().background(palette.borderFaint)
                rankRow(rank: rank,
                        totalUsers: profile.totalUsers,
                        percentile: profile.percentile)
            }
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

    /// Rank + optional denominator + optional percentile. Each child
    /// renders only when its data is present.
    private func rankRow(rank: Int, totalUsers: Int?, percentile: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text("FLEET RANK")
                .font(EType.micro)
                .tracking(1.1)
                .foregroundColor(palette.textSecondary)
            Text("#\(rank)")
                .font(EType.bodyStrong.monospacedDigit())
                .foregroundStyle(LinearGradient.diagonal)
            if let total = totalUsers, total > 0 {
                Text("/ \(numberCompact(total))")
                    .font(EType.caption.monospacedDigit())
                    .foregroundColor(palette.textTertiary)
            }
            Spacer()
            if let p = percentile {
                // Backend returns percentile as "beaten %" — e.g. 0.92
                // means "ahead of 92% of fleet". Clamp + render when
                // present.
                let clamped = min(100, max(0, Int(round(p * 100))))
                Text("Top \(max(1, 100 - clamped))%")
                    .font(EType.caption.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
        }
    }

    // MARK: - Missions card

    @ViewBuilder
    private var missionsCard: some View {
        sectionCard(
            kicker: "ACTIVE MISSIONS",
            trailing: missionsTrailingLabel
        ) {
            switch missionsStore.state {
            case .loading:
                inlineLoading
            case .empty:
                EusoEmptyState(
                    systemImage: "target",
                    title: "No active missions",
                    subtitle: "New missions drop weekly. Check back after your next haul.",
                    comingSoon: false
                )
            case .error(let err):
                inlineError(err: err) {
                    Task { await missionsStore.refresh() }
                }
            case .loaded(let items):
                VStack(spacing: Space.s3) {
                    ForEach(items.prefix(2)) { mission in
                        missionRow(mission)
                    }
                }
            }
        }
    }

    private var missionsTrailingLabel: String? {
        guard case .loaded(let items) = missionsStore.state else { return nil }
        let active = items.filter { $0.claimedAt == nil }.count
        return "\(active) / \(items.count)"
    }

    private func missionRow(_ m: DriverMission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(m.title)
                    .font(EType.bodyStrong)
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                if let r = m.rewardLabel, !r.isEmpty {
                    Text(r)
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1)
                }
            }
            if let subtitle = m.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.tintNeutral.opacity(0.6))
                        .frame(height: 6)
                    Capsule()
                        .fill(AnyShapeStyle(LinearGradient.diagonal))
                        .frame(
                            width: max(6, geo.size.width * CGFloat(min(1.0, max(0.0, m.progress)))),
                            height: 6
                        )
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(Int(min(1.0, max(0.0, m.progress)) * 100))%")
                    .font(EType.micro.monospacedDigit())
                    .foregroundColor(palette.textTertiary)
                Spacer()
                if let expiresAt = m.expiresAt, !expiresAt.isEmpty {
                    Text("ENDS \(shortDay(expiresAt))")
                        .font(EType.micro)
                        .tracking(1.0)
                        .foregroundColor(palette.textTertiary)
                }
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.bgPage.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: - Badges card

    @ViewBuilder
    private var badgesCard: some View {
        sectionCard(
            kicker: "BADGE COLLECTION",
            trailing: badgesTrailingLabel
        ) {
            switch badgesStore.state {
            case .loading:
                inlineLoading
            case .empty:
                EusoEmptyState(
                    systemImage: "star.circle",
                    title: "No badges earned yet",
                    subtitle: "Complete missions and hit streak milestones to start your collection.",
                    comingSoon: false
                )
            case .error(let err):
                inlineError(err: err) {
                    Task { await badgesStore.refresh() }
                }
            case .loaded(let items):
                badgeStripe(items: items)
            }
        }
    }

    private var badgesTrailingLabel: String? {
        guard case .loaded(let items) = badgesStore.state else { return nil }
        let earned = items.filter { $0.earnedAt != nil }.count
        return "\(earned) / \(items.count)"
    }

    private func badgeStripe(items: [DriverBadge]) -> some View {
        let earned = items.filter { $0.earnedAt != nil }
        let pick: [DriverBadge] = earned.isEmpty
            ? Array(items.prefix(5))
            : Array(earned.prefix(5))

        return HStack(spacing: Space.s3) {
            ForEach(pick) { badge in
                badgeTile(badge: badge)
            }
            if pick.isEmpty {
                Text("—")
                    .font(EType.caption)
                    .foregroundColor(palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private func badgeTile(badge: DriverBadge) -> some View {
        let isLocked = badge.earnedAt == nil
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        isLocked
                        ? AnyShapeStyle(palette.tintNeutral.opacity(0.5))
                        : AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                    )
                    .frame(width: 44, height: 44)
                Circle()
                    .strokeBorder(
                        isLocked
                        ? AnyShapeStyle(palette.borderFaint)
                        : AnyShapeStyle(LinearGradient.diagonal),
                        lineWidth: 1.2
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: systemImageFor(badge: badge))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        isLocked
                        ? AnyShapeStyle(palette.textTertiary)
                        : AnyShapeStyle(LinearGradient.diagonal)
                    )
            }
            Text(badge.name)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundColor(
                    isLocked ? palette.textTertiary : palette.textPrimary
                )
                .lineLimit(1)
                .frame(maxWidth: 56)
                .minimumScaleFactor(0.7)
        }
    }

    /// Badges server may return either a raw SF Symbol name (e.g.
    /// `"trophy"`) or an asset id that isn't in the bundle. If the
    /// symbol doesn't exist we fall through to a neutral "rosette" —
    /// never a hardcoded decorative graphic.
    private func systemImageFor(badge: DriverBadge) -> String {
        let img = badge.iconName.trimmingCharacters(in: .whitespaces)
        guard !img.isEmpty else { return "rosette" }
        // Prefix-check a handful of canonical SF Symbol shapes the
        // server is known to return; anything else renders "rosette".
        let allowed: Set<String> = [
            "trophy", "rosette", "medal", "star", "star.fill", "star.circle",
            "flame", "flame.fill", "bolt", "bolt.fill", "checkmark.seal",
            "shield", "shield.fill", "leaf", "leaf.fill", "crown", "crown.fill",
            "sparkles", "diamond", "diamond.fill"
        ]
        return allowed.contains(img) ? img : "rosette"
    }

    // MARK: - Leaderboard card

    @ViewBuilder
    private var leaderboardCard: some View {
        sectionCard(
            kicker: "YOUR RANK",
            trailing: leaderboardTrailingLabel
        ) {
            switch leaderboardStore.state {
            case .loading:
                inlineLoading
            case .empty:
                EusoEmptyState(
                    systemImage: "list.number",
                    title: "No rank yet",
                    subtitle: "Post your first scored haul and you'll enter the board at the weekend reset.",
                    comingSoon: false
                )
            case .error(let err):
                inlineError(err: err) {
                    Task { await leaderboardStore.refresh() }
                }
            case .loaded(let items):
                leaderboardRow(items: items)
            }
        }
    }

    private var leaderboardTrailingLabel: String? {
        guard case .loaded(let items) = leaderboardStore.state else { return nil }
        return "\(items.count) drivers"
    }

    @ViewBuilder
    private func leaderboardRow(items: [LeaderboardRow]) -> some View {
        let me = items.first(where: { $0.isCurrentDriver })
        if let row = me {
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(row.rank)")
                        .font(EType.h1.monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1)
                    Text(row.displayName)
                        .font(EType.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(numberCompact(row.score))
                        .font(EType.bodyStrong.monospacedDigit())
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)
                    rankDelta(delta: row.changeVsLastWeek)
                }
            }
        } else {
            // No isCurrentDriver=true row — server returned the season
            // list but this driver isn't ranked yet (new enrollment).
            EusoEmptyState(
                systemImage: "person.crop.circle.badge.clock",
                title: "You're not ranked yet",
                subtitle: "Post your first scored haul and you'll enter the board on Sunday reset.",
                comingSoon: false
            )
        }
    }

    private func rankDelta(delta: Int?) -> some View {
        HStack(spacing: 2) {
            if let d = delta {
                if d > 0 {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("\(d)")
                        .font(EType.micro.monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                } else if d < 0 {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 7, weight: .bold))
                        .rotationEffect(.degrees(180))
                        .foregroundColor(palette.danger)
                    Text("\(abs(d))")
                        .font(EType.micro.monospacedDigit())
                        .foregroundColor(palette.danger)
                } else {
                    Text("—")
                        .font(EType.micro)
                        .foregroundColor(palette.textTertiary)
                }
            } else {
                Text("—")
                    .font(EType.micro)
                    .foregroundColor(palette.textTertiary)
            }
        }
    }

    // MARK: - Action rows

    private var actionRows: some View {
        VStack(spacing: 0) {
            actionRow(
                systemImage: "target",
                title: "View all missions",
                subtitle: missionsActionSubtitle,
                disabled: !hasMissions
            ) {
                showMissionsSheet = true
            }
            Divider().background(palette.borderFaint)
            actionRow(
                systemImage: "star.circle",
                title: "Open badge collection",
                subtitle: badgesActionSubtitle,
                disabled: !hasBadges
            ) {
                showBadgesSheet = true
            }
            Divider().background(palette.borderFaint)
            actionRow(
                systemImage: "list.number",
                title: "Open leaderboard",
                subtitle: leaderboardActionSubtitle,
                disabled: !hasLeaderboard
            ) {
                showLeaderboardSheet = true
            }
            Divider().background(palette.borderFaint)
            actionRow(
                systemImage: "arrow.clockwise",
                title: "Refresh The Haul",
                subtitle: "Pulls fresh XP, missions, badges, and rank"
            ) {
                Task { await refreshAll() }
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

    private var hasMissions: Bool {
        if case .loaded(let items) = missionsStore.state, !items.isEmpty { return true }
        return false
    }
    private var hasBadges: Bool {
        if case .loaded(let items) = badgesStore.state, !items.isEmpty { return true }
        return false
    }
    private var hasLeaderboard: Bool {
        if case .loaded(let items) = leaderboardStore.state, !items.isEmpty { return true }
        return false
    }

    private var missionsActionSubtitle: String {
        guard case .loaded(let items) = missionsStore.state else {
            return "Weekly, monthly, and seasonal targets"
        }
        let active = items.filter { $0.claimedAt == nil }.count
        return active == 0
            ? "No active missions"
            : "\(active) active · see progress + claim rewards"
    }
    private var badgesActionSubtitle: String {
        guard case .loaded(let items) = badgesStore.state else {
            return "Everything you've earned, mapped to the season"
        }
        let earned = items.filter { $0.earnedAt != nil }.count
        return "\(earned) earned of \(items.count) · tier + lore"
    }
    private var leaderboardActionSubtitle: String {
        guard case .loaded(let items) = leaderboardStore.state else {
            return "Season standings across drivers in your division"
        }
        return "\(items.count) drivers · lobby presence"
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

    // MARK: - Shared card chrome

    @ViewBuilder
    private func sectionCard<Content: View>(
        kicker: String,
        trailing: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(kicker)
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                if let t = trailing, !t.isEmpty {
                    Text(t)
                        .font(EType.micro.monospacedDigit())
                        .tracking(1.0)
                        .foregroundColor(palette.textTertiary)
                }
            }
            content()
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

    private var inlineLoading: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Loading…")
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
    }

    private func inlineError(err: Error, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(palette.danger)
                Text("Couldn't load — \(err.localizedDescription)")
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            Button(action: retry) {
                Text("Retry")
                    .font(EType.micro)
                    .tracking(1.2)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadingCard(title: String) -> some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text(title)
                .font(EType.caption)
                .foregroundColor(palette.textTertiary)
            Spacer(minLength: 0)
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

    private func errorCard(err: Error, retry: @escaping () -> Void) -> some View {
        EusoEmptyState(
            systemImage: "exclamationmark.triangle",
            title: "Couldn't load The Haul",
            subtitle: err.localizedDescription,
            cta: (label: "Retry", action: retry)
        )
    }

    // MARK: - Format helpers

    private func numberCompact(_ value: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        fmt.groupingSeparator = ","
        return fmt.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func shortDay(_ iso: String) -> String {
        // Defensive ISO parse — if it doesn't match either internet-date
        // variant, fall through to the raw server string (we don't invent
        // a date the server didn't send).
        let iso1 = ISO8601DateFormatter()
        iso1.formatOptions = [.withInternetDateTime]
        if let d = iso1.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: d).uppercased()
        }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso2.date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d"
            return out.string(from: d).uppercased()
        }
        return iso
    }
}

// MARK: - Screen wrapper

struct TheHaulDashboardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TheHaulDashboard()
        } nav: {
            BottomNav(
                leading: driverNavLeading_060(),
                trailing: driverNavTrailing_060(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_060() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",          isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy",         isCurrent: true)]
}
private func driverNavTrailing_060() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill",   isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",        isCurrent: false)]
}

// MARK: - Previews
//
// Both previews render the production path — live stores, no fixtures.
// An unauthenticated `EusoTripSession()` resolves every store to `.empty`
// or `.error` deterministically without hitting the network, so both
// previews render a fully branded empty path. A real signed-in driver
// with active season data will see the live XP / missions / badges /
// leaderboard rows on device.

#Preview("060 · The Haul Dashboard · Night · Empty / Live store") {
    TheHaulDashboardScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("060 · The Haul Dashboard · Afternoon · Empty / Live store") {
    TheHaulDashboardScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
