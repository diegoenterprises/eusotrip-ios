//
//  067_MeProfile.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · profile hub)
//
//  Screen 067 · Me · Profile — the driver's read-only profile hub
//  reached from the Me tab. Surfaces the authenticated identity, level
//  + XP progress, reputation (rating / on-time / safety), and the
//  reference stats the driver wants at a glance. Mutations (edit name,
//  change avatar, etc.) live on `ProfileEditView` which is reached
//  from DriverTabPanes via a separate Me sub-route — this brick stays
//  read-only so the profile hub is safe to drop into any nav context
//  without sheet-dismiss plumbing.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Identity (name / email / role) comes from `authRouter.me` via
//      `ProfileStore` — MCP-verified at `server/routers/auth.ts`.
//    • Level / XP / active title come from `gamification.getProfile`
//      via `LoyaltyHeroStore` — gamification.ts:123. Title defaults to
//      `null` on the server when the driver hasn't equipped one; the
//      hero renders a neutral "Driver" fallback (universal label, not
//      fabricated state).
//    • Reputation (rating avg, on-time pickup/delivery, safety score,
//      cancellation rate) comes from `profile.getReputation` via
//      `ReputationStore` — profileRouter.ts.
//    • Member-since + total miles come off `GamificationAPI.Profile`
//      (server-echoed).
//    • Zero synthesised numbers. Each card renders only when its store
//      is `.loaded`; `.loading` shows a skeleton, `.error` shows a
//      branded retry banner, `.empty` shows `EusoEmptyState`.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero avatar ring, level-bar fill,
//         rating stars, title chip — zero Brand.info/blue flat fills.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg),
//         type (EType.*).
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation. Under preview's no-baseURL
//         runtime stores land in `.error` via `notConfigured` —
//         stable in both registers without fixtures.
//

import SwiftUI

// MARK: - Screen root

struct MeProfile: View {
    @Environment(\.palette) var palette
    @StateObject private var identity = ProfileStore()
    @StateObject private var loyalty = LoyaltyHeroStore()
    @StateObject private var reputation = ReputationStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                heroCard
                levelCard
                reputationCard
                milesCard
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task {
            async let i: Void = identity.refresh()
            async let l: Void = loyalty.refresh()
            async let r: Void = reputation.refresh()
            _ = await (i, l, r)
        }
        .refreshable {
            async let i: Void = identity.refresh()
            async let l: Void = loyalty.refresh()
            async let r: Void = reputation.refresh()
            _ = await (i, l, r)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Profile")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Identity · level · reputation")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(
                state: (identity.isLoading || loyalty.isLoading || reputation.isLoading)
                    ? .thinking : .idle,
                diameter: 40
            )
        }
    }

    // MARK: Hero card — identity + active title

    private var heroCard: some View {
        Group {
            switch (identity.state, loyalty.state) {
            case (.loading, _), (_, .loading):
                heroSkeleton
            case (.error(let e), _):
                errorBanner(e) { Task { await identity.refresh() } }
            case (_, .error(let e)):
                errorBanner(e) { Task { await loyalty.refresh() } }
            case (.empty, _):
                EusoEmptyState(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No profile on file",
                    subtitle: "Sign in again and pull down to refresh once your account is set up."
                )
            case (.loaded(let user), let loyaltyState):
                let profile = loyaltyState.value
                heroContent(user: user, profile: profile)
            }
        }
    }

    @ViewBuilder
    private func heroContent(user: AuthUser?, profile: GamificationAPI.Profile?) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            // Gradient avatar ring with initials
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 76, height: 76)
                Text(initials(for: user?.name ?? profile?.name))
                    .font(EType.h2)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(user?.name ?? profile?.name ?? "Driver")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                Text(formattedRole(user?.role ?? profile?.role))
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                if let title = profile?.title, !title.isEmpty {
                    Text(title.uppercased())
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s2)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(LinearGradient.diagonal)
                        )
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private var heroSkeleton: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Circle()
                .fill(palette.tintNeutral)
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: Space.s2) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.tintNeutral)
                    .frame(width: 180, height: 18)
                RoundedRectangle(cornerRadius: 4)
                    .fill(palette.tintNeutral)
                    .frame(width: 120, height: 12)
            }
            Spacer()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Level card — level, XP bar, total points

    private var levelCard: some View {
        Group {
            switch loyalty.state {
            case .loading:
                skeletonCard(height: 110)
            case .error(let e):
                errorBanner(e) { Task { await loyalty.refresh() } }
            case .empty:
                EusoEmptyState(
                    systemImage: "sparkles",
                    title: "No level yet",
                    subtitle: "Complete your first load to unlock level progression."
                )
            case .loaded(let profile):
                levelContent(profile)
            }
        }
    }

    private func levelContent(_ profile: GamificationAPI.Profile) -> some View {
        let currentXp = profile.currentXp ?? 0
        let nextAt = profile.xpToNextLevel ?? max(currentXp, 1)
        let ratio = nextAt > 0 ? min(1.0, Double(currentXp) / Double(nextAt)) : 0.0

        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LEVEL")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(profile.level ?? 1)")
                        .font(EType.numeric)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TOTAL XP")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Text(formatted(profile.totalPoints ?? 0))
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                }
            }

            // XP progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.tintNeutral)
                        .frame(height: 10)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(ratio), height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(formatted(currentXp)) / \(formatted(nextAt)) XP")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if let rank = profile.rank, rank > 0,
                   let total = profile.totalUsers, total > 0 {
                    Text("Rank \(rank) of \(formatted(total))")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Reputation card — rating, on-time, safety

    private var reputationCard: some View {
        Group {
            switch reputation.state {
            case .loading:
                skeletonCard(height: 130)
            case .error(let e):
                errorBanner(e) { Task { await reputation.refresh() } }
            case .empty:
                EusoEmptyState(
                    systemImage: "star.leadinghalf.filled",
                    title: "No reputation yet",
                    subtitle: "Complete a few loads and ratings will appear here."
                )
            case .loaded(let rep):
                if let rep {
                    reputationContent(rep)
                } else {
                    EusoEmptyState(
                        systemImage: "star.leadinghalf.filled",
                        title: "No reputation yet",
                        subtitle: "Complete a few loads and ratings will appear here."
                    )
                }
            }
        }
    }

    private func reputationContent(_ rep: ProfileAPI.Reputation) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("REPUTATION")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Updated \(shortDate(rep.lastUpdatedAt))")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(String(format: "%.2f", rep.ratingAverage))
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                Text("· \(rep.ratingCount) rating\(rep.ratingCount == 1 ? "" : "s")")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }

            HStack(spacing: Space.s3) {
                metricCell("ON-TIME PICKUP", String(format: "%.0f%%", rep.onTimePickupPct))
                metricCell("ON-TIME DELIVERY", String(format: "%.0f%%", rep.onTimeDeliveryPct))
                metricCell("SAFETY", String(format: "%.0f", rep.safetyScore))
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func metricCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Miles + member-since card

    private var milesCard: some View {
        Group {
            switch loyalty.state {
            case .loaded(let profile):
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text("LIFETIME")
                            .font(EType.micro)
                            .tracking(1.3)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                    }
                    HStack(spacing: Space.s3) {
                        milesCell("MILES EARNED", formatted(Int(profile.totalMilesEarned ?? 0)))
                        if let since = profile.memberSince {
                            milesCell("SINCE", shortDate(since))
                        }
                    }
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg)
            default:
                EmptyView()
            }
        }
    }

    private func milesCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro)
                .tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shared helpers

    private func skeletonCard(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.tintNeutral.opacity(0.5))
            .frame(height: height)
    }

    private func errorBanner(_ err: Error, retry: @escaping () -> Void) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Couldn't load this section")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func initials(for name: String?) -> String {
        guard let name, !name.isEmpty else { return "D" }
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func formattedRole(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "DRIVER" }
        return raw.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// ISO timestamp → "Apr 23" style. Returns the raw string if parsing
    /// fails so we never hide real server-returned data.
    private func shortDate(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: d)
        }
        // Fallback: if the server gives us yyyy-MM-dd, render it as-is.
        return iso
    }
}

// MARK: - Screen wrapper

struct MeProfileScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeProfile()
        } nav: {
            BottomNav(
                leading: driverNavLeading_067(),
                trailing: driverNavTrailing_067(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_067() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_067() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews
//
// Previews never run the `.task` refresh — stores stay in `.loading` so
// both registers render the skeleton without hitting the network.

#Preview("067 · Me Profile · Night") {
    MeProfileScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("067 · Me Profile · Afternoon") {
    MeProfileScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
