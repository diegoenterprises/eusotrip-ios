//
//  TheHaulShell.swift
//  EusoTrip — The Haul (P1) · the unified push-nav shell.
//
//  Replaces the slide-up MeHaulView modal with a real push-nav destination
//  (registry id "060"). Bespoke EusoHeader chrome + iridescent hairline + a
//  persistent Season-Standing hero (real gamification profile, honest empty
//  state) sitting above the lifted Lobby / Missions / Rewards / Leaderboard
//  tab switcher. The four tab bodies are the existing live tabs (promoted to
//  internal); the Season Hero is the PR1 HaulPrimitives.HaulSeasonHero.
//
//  Vocabulary: Standing / Miles-Earned (the Trillion-Dollar doctrine).
//  Reached via the driver "Haul" BottomNav slot today; after PR4 every former
//  modal entry point (Home tile, Me-hub row, ESANG voice) pushes here too.
//
//  Powered by ESANG AI™.
//

import SwiftUI

/// Honest payload for the mission-claim Recognition reveal — the mission
/// name + the exact Miles the server credits (Mission.xpReward). Carries NO
/// fabricated balance / level / badge / rolled cosmetic crate (none of those
/// come back through the claim response; the cosmetic crate rolls at POD in a
/// later PR).
struct HaulClaimReveal: Identifiable {
    let id: Int
    let missionName: String
    let miles: Int?
}

struct TheHaulShell: View {
    @Environment(\.palette) private var palette
    @State private var tab: HaulTab = .lobby
    @State private var profile: GamificationAPI.Profile?
    @State private var loadedProfile = false
    @State private var claimReveal: HaulClaimReveal? = nil

    enum HaulTab: String, CaseIterable, Identifiable {
        case lobby, missions, rewards, leaderboard
        var id: String { rawValue }
        var label: String {
            switch self {
            case .lobby:       return "Lobby"
            case .missions:    return "Missions"
            case .rewards:     return "Rewards"
            case .leaderboard: return "Leaderboard"
            }
        }
        var icon: String {
            switch self {
            case .lobby:       return "bubble.left.and.bubble.right"
            case .missions:    return "flag.checkered"
            case .rewards:     return "gift"
            case .leaderboard: return "trophy"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EusoHeader(
                title: "The Haul",
                supertitle: headerSupertitle,
                subtitle: "Standings · missions · rewards"
            )
            IridescentHairline()

            TileStack(alignment: .leading, spacing: Space.s4) {
                seasonHero
                tabPicker
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)

            // The Lobby (chat component) and Leaderboard self-scroll;
            // Missions and Rewards are bare VStacks (authored to sit inside
            // MeDetailContainer's ScrollView in the old modal path), so the
            // shell scrolls those two itself — otherwise a tall mission/reward
            // list overflows the fixed shell height with no way to reach the
            // bottom rows.
            Group {
                switch tab {
                case .lobby:       HaulLobbyTab()
                case .missions:    ScrollView(showsIndicators: false) {
                    HaulMissionsTab(onClaimReveal: { reveal in
                        withAnimation(.easeInOut(duration: 0.25)) { claimReveal = reveal }
                    }).padding(.bottom, Space.s5)
                }
                case .rewards:     ScrollView(showsIndicators: false) { HaulRewardsTab().padding(.bottom, Space.s5) }
                case .leaderboard: HaulLeaderboardTab()
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task {
            guard !loadedProfile else { return }
            loadedProfile = true
            profile = try? await EusoTripAPI.shared.gamification.getProfile()
        }
        // Full-bleed Recognition reveal on a successful mission claim. Hosted
        // at the shell level (NOT inside the missions ScrollView) so the scrim
        // covers the whole shell instead of being clipped to scroll content.
        .overlay {
            if let r = claimReveal {
                PostLoadPostedCelebration(
                    loadNumber: "",
                    headline: "Recognition Earned",
                    subline: r.missionName,
                    ctaTitle: "Continue",
                    milesEarned: r.miles,
                    hapticOnAppear: true,
                    accessibilityLabelOverride: "Recognition earned. \(r.missionName)."
                        + (r.miles.map { " \($0) miles earned." } ?? ""),
                    onContinue: { withAnimation(.easeInOut(duration: 0.2)) { claimReveal = nil } }
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
    }

    private var headerSupertitle: String {
        guard let t = profile?.title, !t.isEmpty else { return "DRIVER · SEASON STANDING" }
        return "DRIVER · \(t.uppercased())"
    }

    // Real gamification profile → Season Hero. Honest: no profile yet → a
    // loading/empty row, never fabricated numbers.
    @ViewBuilder private var seasonHero: some View {
        if let m = seasonModel {
            HaulSeasonHero(model: m)
        } else {
            HStack(spacing: Space.s2) {
                ProgressView().tint(palette.textSecondary)
                Text(loadedProfile
                     ? "Your season standing builds as you run loads."
                     : "Loading your standing…")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg)
                        .strokeBorder(palette.borderFaint, lineWidth: 1))
            )
        }
    }

    private var seasonModel: HaulSeasonHeroModel? {
        guard let p = profile else { return nil }
        let lvl = p.level ?? 1
        let standing = (p.title?.isEmpty == false) ? (p.title ?? "Rookie") : "Rookie"
        let xp = p.currentXp ?? Int((p.currentMiles ?? 0).rounded())
        let toNext = p.xpToNextLevel ?? 0
        let target = p.nextLevelAt ?? (xp + max(1, toNext))
        let sub = (p.rank != nil && p.totalUsers != nil)
            ? "rank \(p.rank!) of \(p.totalUsers!)"
            : "Your season standing"
        let nextLine = toNext > 0
            ? "\(toNext.formatted()) Miles to next Standing"
            : "Top Standing reached"
        return HaulSeasonHeroModel(
            season: "THE HAUL",
            tier: "STANDING · \(standing.uppercased())",
            name: "Standing \(lvl)",
            sub: sub,
            milesLabel: "MILES EARNED",
            miles: xp,
            milesTarget: target,
            nextTierLine: nextLine
        )
    }

    // Lifted verbatim from MeHaulView — the segmented pill bar.
    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(HaulTab.allCases) { t in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = t }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: t.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(t.label)
                                .font(EType.caption)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(tab == t
                                ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.22))
                                : AnyShapeStyle(palette.bgCardSoft))
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                tab == t ? Color.clear : palette.borderFaint, lineWidth: 1)
                        )
                        .foregroundStyle(tab == t
                            ? AnyShapeStyle(LinearGradient.diagonal)
                            : AnyShapeStyle(palette.textSecondary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Screen wrapper (Shell + BottomNav; registry id "060")

struct TheHaulShellScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            TheHaulShell()
        } nav: {
            BottomNav(
                leading: driverNavLeading_haul(),
                trailing: driverNavTrailing_haul(),
                orbState: .idle
            )
        }
    }
}

// Driver BottomNav slots — identical to 060's (never alter the BottomNav design):
// Home / Haul (leading), My Loads / Me (trailing); Haul current. Tap routing is
// injected app-side via .driverNavHandler, so onTap stays default.
private func driverNavLeading_haul() -> [NavSlot] {
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_haul() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("The Haul Shell · Night") {
    TheHaulShellScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("The Haul Shell · Day") {
    TheHaulShellScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
