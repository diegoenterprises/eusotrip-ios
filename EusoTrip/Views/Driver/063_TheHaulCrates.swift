//
//  063_TheHaulCrates.swift
//  EusoTrip 2027 UI — Wave 7 (driver · The Haul · crates vault)
//
//  Screen 063 · The Haul · Crates — the mystery-reward vault surface
//  that caps the gamification sub-wave alongside 060 Dashboard, 061
//  Missions, 062 Badges, and 064 Leaderboard. Drivers earn crates by
//  completing missions, extending streaks, hitting tier thresholds,
//  and winning seasonal tournaments. Opening a crate emits a server-
//  rolled payload of XP + EusoMiles that's committed directly to the
//  gamification profile.
//
//  Cohort B — fully dynamic (retyped from A in the 65th firing)
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data"):
//
//    • Every rendered crate row comes from the live tRPC surface
//      `gamification.getCrates` (MCP-verified at
//      `frontend/server/routers/gamification.ts:1039`). `CratesStore`
//      in `ViewModels/LiveDataStores.swift` owns the fetch + the
//      opened-reveal state.
//    • Opening a crate fires `gamification.openCrate({ crateId })`
//      (gamification.ts:1066). The server rolls the drop table,
//      commits XP + miles to `gamificationProfiles`, and returns the
//      rolled contents — the iOS layer renders what came back, never
//      rolling locally.
//    • Empty state is a real server-confirmed empty — the hero shows
//      a branded `EusoEmptyState("No crates yet")` when the driver
//      has nothing pending, which means "the server returned zero
//      rows," not "coming soon."
//    • The concept card remains as evergreen product copy describing
//      what tiers exist and how crates are earned. Tier labels
//      (common / rare / legendary / etc.) are universal rarity
//      vocabulary, not driver-specific state.
//
//  Doctrine refs:
//    §2 Gradient-only brand accents — every tier ring, CTA, and
//       reveal-sheet chip uses `LinearGradient.diagonal`.
//    §4 Tokenized spacing (`Space.sN`), radii (`Radius.sm/md/lg/xl`),
//       type (`EType.*`). No magic numbers.
//    §5 Palette semantic — `palette.textPrimary/Secondary/Tertiary`,
//       `palette.bgCard/bgPage`, `palette.borderFaint`,
//       `palette.tintNeutral`. No hard-coded Color literals.
//    §7 Previews in both registers.
//    §10 Previews compile in isolation — the store stays in `.loading`
//        (default) so both previews render the loading skeleton
//        without hitting the network. No fixtures.
//

import SwiftUI

// MARK: - Tier vocabulary (evergreen rarity language, not server data)
//
// Backend `crateType` is one of: common | uncommon | rare | epic |
// legendary | mythic. These are universal rarity labels shared across
// every game-like UI, not driver-specific state. Color + glyph ride
// here so the screen can present a live crate row without inventing
// any data the server didn't send.

private struct CrateTierStyle {
    let label: String
    let glyph: String
    let intensity: Double   // 0…1 — drives gradient opacity on the ring
}

private func style(for crateType: String) -> CrateTierStyle {
    switch crateType.lowercased() {
    case "common":    return CrateTierStyle(label: "Common",    glyph: "shippingbox",       intensity: 0.35)
    case "uncommon":  return CrateTierStyle(label: "Uncommon",  glyph: "shippingbox.fill",  intensity: 0.50)
    case "rare":      return CrateTierStyle(label: "Rare",      glyph: "cube",              intensity: 0.70)
    case "epic":      return CrateTierStyle(label: "Epic",      glyph: "cube.fill",         intensity: 0.85)
    case "legendary": return CrateTierStyle(label: "Legendary", glyph: "sparkles",          intensity: 0.95)
    case "mythic":    return CrateTierStyle(label: "Mythic",    glyph: "sparkles.tv",       intensity: 1.00)
    default:          return CrateTierStyle(label: crateType.capitalized, glyph: "shippingbox", intensity: 0.55)
    }
}

// MARK: - Screen root

struct TheHaulCrates: View {
    @Environment(\.palette) var palette
    @StateObject private var store = CratesStore()

    /// The crate the driver just tapped to open — drives the confirm
    /// sheet. Separate from `store.lastReveal` so we can distinguish
    /// "about to open" vs "reveal the server's roll."
    @State private var pendingOpen: GamificationAPI.Crate?

    /// Flipped on by `.onChange(of: store.lastReveal)` so the reveal
    /// sheet presents exactly once per successful open. Avoids the
    /// "binding regenerates identity on every read" trap.
    @State private var showReveal: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    loadingSkeleton
                case .empty:
                    emptyHero
                case .error(let err):
                    errorBanner(err)
                case .loaded(let crates):
                    cratesGrid(crates)
                }
                conceptCard
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $pendingOpen) { crate in
            openConfirmSheet(for: crate)
                .environment(\.palette, palette)
                .presentationDetents([.medium])
                .eusoCloseX()
        }
        .sheet(isPresented: $showReveal, onDismiss: {
            // Clearing `lastReveal` on dismiss makes the next successful
            // open transition nil → non-nil, which is what `onChange`
            // watches. Otherwise two back-to-back opens with identical
            // rolled contents would miss the second presentation.
            store.lastReveal = nil
        }) {
            if let payload = store.lastReveal {
                revealSheet(payload)
                    .environment(\.palette, palette)
                    .presentationDetents([.medium])
                    .eusoCloseX()
            }
        }
        .onChange(of: store.lastReveal) { _, newValue in
            showReveal = (newValue != nil)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Crates")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Vault · mystery drops and seasonal cosmetics")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States — loading / empty / error / loaded

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s3) {
            ProgressView()
                .tint(palette.textSecondary)
            Text("Checking the vault…")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "shippingbox.and.arrow.backward",
            title: "No crates yet",
            subtitle: "Finish missions, extend streaks, or place in a seasonal tournament to earn a crate. Drops are committed server-side — what shows up here is exactly what you'll open."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't reach the vault")
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

    private func cratesGrid(_ crates: [GamificationAPI.Crate]) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("READY TO OPEN")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(crates.count) pending")
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.s3),
                    GridItem(.flexible(), spacing: Space.s3)
                ],
                spacing: Space.s3
            ) {
                ForEach(crates) { crate in
                    Button {
                        pendingOpen = crate
                    } label: {
                        crateTile(crate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func crateTile(_ crate: GamificationAPI.Crate) -> some View {
        let s = style(for: crate.crateType)
        return VStack(alignment: .center, spacing: Space.s2) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal.opacity(s.intensity))
                    .frame(width: 60, height: 60)
                Image(systemName: s.glyph)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(s.label.uppercased())
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textPrimary)
            if let src = crate.source, !src.isEmpty {
                Text(src.uppercased())
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s4)
        .padding(.horizontal, Space.s2)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Sheets

    private func openConfirmSheet(for crate: GamificationAPI.Crate) -> some View {
        let s = style(for: crate.crateType)
        return VStack(spacing: Space.s4) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal.opacity(s.intensity))
                    .frame(width: 92, height: 92)
                Image(systemName: s.glyph)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, Space.s5)
            Text("Open \(s.label) crate?")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Text("The server rolls contents the moment you tap. You'll see what you pulled on the next screen.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s5)
            Button {
                let capture = crate
                pendingOpen = nil
                Task { await store.openCrate(capture) }
            } label: {
                Text("Open")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.s5)
            Button {
                pendingOpen = nil
            } label: {
                Text("Cancel")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, Space.s5)
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgPage.ignoresSafeArea())
    }

    private func revealSheet(_ response: GamificationAPI.OpenCrateResponse) -> some View {
        VStack(spacing: Space.s4) {
            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, Space.s5)
            Text(response.success ? "You pulled…" : "Couldn't open")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)

            if response.success {
                VStack(spacing: Space.s2) {
                    ForEach(response.contents ?? [], id: \.self) { reward in
                        HStack(spacing: Space.s2) {
                            Image(systemName: reward.type == "xp" ? "star.fill" : "flame.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LinearGradient.diagonal)
                                .frame(width: 28)
                            Text(reward.name)
                                .font(EType.body)
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, Space.s4)
                        .padding(.vertical, Space.s2)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(palette.bgCard)
                        )
                    }
                }
                .padding(.horizontal, Space.s5)
            } else if let message = response.message {
                Text(message)
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s5)
            }

            Button {
                store.lastReveal = nil
            } label: {
                Text("Close")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(LinearGradient.diagonal)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.s5)
            .padding(.bottom, Space.s5)
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgPage.ignoresSafeArea())
    }

    // MARK: Concept card — evergreen product documentation

    private var conceptCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("HOW CRATES WORK")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
            }

            Text("Crates are mystery boxes you earn by driving, not by paying.")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.s2) {
                conceptBullet(
                    systemImage: "checkmark.seal",
                    text: "Clear missions, extend streaks, hit tier thresholds — each drops the matching rarity."
                )
                conceptBullet(
                    systemImage: "gift",
                    text: "Every open commits XP + EusoMiles to your profile server-side. What you see is what you got."
                )
                conceptBullet(
                    systemImage: "calendar.badge.clock",
                    text: "Seasonal tournaments seed legendary-tier crates with limited-edition drops."
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
}

// MARK: - Screen wrapper

struct TheHaulCratesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TheHaulCrates()
        } nav: {
            BottomNav(
                leading: driverNavLeading_063(),
                trailing: driverNavTrailing_063(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_063() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: true)]
}
private func driverNavTrailing_063() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Previews
//
// Previews never run the `.task` refresh — the store stays in `.loading`
// so both registers render the loading skeleton without hitting the
// network. No fixtures.

#Preview("063 · The Haul Crates · Night") {
    TheHaulCratesScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("063 · The Haul Crates · Afternoon") {
    TheHaulCratesScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
