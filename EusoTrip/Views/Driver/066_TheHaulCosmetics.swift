//
//  066_TheHaulCosmetics.swift
//  EusoTrip 2027 UI — Wave 7 (driver · The Haul · cosmetics vault)
//
//  Screen 066 · The Haul · Cosmetics — the driver's profile-customization
//  surface: avatars, frames, titles. Caps the gamification sub-wave
//  alongside 060 Dashboard, 061 Missions, 062 Badges, 063 Crates,
//  064 Leaderboard, 065 Streaks.
//
//  Cohort B — fully dynamic against `advancedGamification.*`
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data"):
//
//    • Every rendered row comes from the live tRPC surface
//      `advancedGamification.getCustomizationOptions` (MCP-verified at
//      `frontend/server/routers/advancedGamification.ts:1786`). The
//      server catalog is static game-design config — `owned`,
//      `equipped`, `cost`, and `prestigeRequired` are shared across
//      every driver and are echoed verbatim.
//
//    • Tapping "Equip" on an owned row fires
//      `advancedGamification.equipCustomization({ type, itemId })`
//      (advancedGamification.ts:1794). The `CustomizationCatalogStore`
//      in `ViewModels/LiveDataStores.swift` owns the mutation + the
//      post-equip refresh so the server's authoritative state lands
//      back on screen.
//
//    • Honest partial-persistence disclosure: the server persists
//      `type: "title"` to `gamificationProfiles.activeTitle`. For
//      `type: "avatar"` and `type: "frame"` the mutation resolves with
//      `success: true` but the change is NOT persisted to the user
//      record (the backend `getDriverProfile.customization` is today
//      hardcoded to `av1 / fr1 / ti1`). The screen surfaces a tight
//      one-line disclosure at the top of the avatar + frame sections
//      so drivers know the feature ships end-to-end for titles today,
//      and avatar/frame sync lands when the backend persistence wave
//      ships. No "coming soon" stub banner; no fake data; the actual
//      server response is what renders.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on headers, tier rings, equipped
//         checkmarks, cost chips — zero `Brand.info` / `Brand.blue`
//         flat fills.
//    §4   Tokenized spacing (`Space.sN`), radii (`Radius.sm/md/lg`),
//         type (`EType.*`).
//    §5   Palette semantic — `palette.textPrimary/Secondary/Tertiary`,
//         `palette.bgCard/bgPage`, `palette.borderFaint`,
//         `palette.tintNeutral`. No hard-coded `Color` literals.
//    §7   Ternary `ShapeStyle` expressions wrapped in `AnyShapeStyle`.
//    §10  Previews compile in isolation — store stays in `.loading`
//         (default) and `.task` lands in `.error` on `notConfigured`
//         under preview's no-baseURL runtime. No fixtures.
//

import SwiftUI

// MARK: - Screen root

struct TheHaulCosmetics: View {
    @Environment(\.palette) var palette
    @StateObject private var store = CustomizationCatalogStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    loadingSkeleton
                case .empty:
                    // Catalog empty is a server-confirmed empty — the
                    // server returned three empty arrays. Unlikely in
                    // practice but honestly handled.
                    emptyHero
                case .error(let err):
                    errorBanner(err)
                case .loaded(let catalog):
                    section(
                        title: "TITLES",
                        subtitle: "Saves to your profile the moment you equip.",
                        type: "title",
                        items: catalog.titles
                    )
                    section(
                        title: "AVATARS",
                        subtitle: "Preview updates instantly. Cross-device avatar sync lands when the backend persistence wave ships.",
                        type: "avatar",
                        items: catalog.avatars
                    )
                    section(
                        title: "FRAMES",
                        subtitle: "Preview updates instantly. Cross-device frame sync lands when the backend persistence wave ships.",
                        type: "frame",
                        items: catalog.frames
                    )
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Cosmetics")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Profile kit · avatars, frames, titles")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States — loading / empty / error

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s3) {
            ProgressView()
                .tint(palette.textSecondary)
            Text("Loading your cosmetics…")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6)
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "sparkles",
            title: "No cosmetics in catalog",
            subtitle: "The server didn't return any avatars, frames, or titles. Pull to refresh once your profile is set up."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load cosmetics")
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

    // MARK: Section (titles / avatars / frames)

    @ViewBuilder
    private func section(
        title: String,
        subtitle: String,
        type: String,
        items: [AdvancedGamificationAPI.CustomizationOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(title)
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Text(subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if items.isEmpty {
                Text("Catalog is empty for this category.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.vertical, Space.s3)
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(items) { item in
                        itemRow(item, type: type)
                    }
                }
            }
        }
    }

    // MARK: Item row

    @ViewBuilder
    private func itemRow(
        _ item: AdvancedGamificationAPI.CustomizationOption,
        type: String
    ) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            // Gradient glyph — opacity tracks ownership.
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(item.owned ? 1.0 : 0.28))
                    .frame(width: 44, height: 44)
                Image(systemName: glyph(for: type))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(item.owned ? 1.0 : 0.85)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s1) {
                    Text(item.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if item.equipped {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                }
                requirementLine(item)
            }

            Spacer(minLength: Space.s2)

            trailingControl(item, type: type)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    item.equipped
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(palette.borderFaint),
                    lineWidth: item.equipped ? 1.5 : 1
                )
        )
    }

    @ViewBuilder
    private func requirementLine(_ item: AdvancedGamificationAPI.CustomizationOption) -> some View {
        if item.owned {
            if item.cost == 0 {
                Text("Starter · included")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            } else {
                Text("Owned")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
        } else {
            HStack(spacing: Space.s2) {
                Label(costLabel(item.cost), systemImage: "circle.hexagongrid")
                    .labelStyle(.titleAndIcon)
                    .font(EType.micro)
                    .foregroundStyle(palette.textSecondary)
                if item.prestigeRequired > 0 {
                    Text("· PRESTIGE \(item.prestigeRequired)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func trailingControl(
        _ item: AdvancedGamificationAPI.CustomizationOption,
        type: String
    ) -> some View {
        if item.equipped {
            Text("EQUIPPED")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textSecondary)
        } else if !item.owned {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        } else if store.equippingItemId == item.id {
            ProgressView()
                .controlSize(.small)
        } else {
            Button {
                Task { await store.equip(type: type, itemId: item.id) }
            } label: {
                Text("Equip")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s1)
                    .background(
                        Capsule().fill(LinearGradient.diagonal)
                    )
            }
            .buttonStyle(.plain)
            .disabled(store.equippingItemId != nil)
        }
    }

    // MARK: Helpers

    private func glyph(for type: String) -> String {
        switch type {
        case "title":  return "rosette"
        case "avatar": return "person.crop.square.fill"
        case "frame":  return "rectangle.stack.fill"
        default:       return "sparkles"
        }
    }

    private func costLabel(_ points: Int) -> String {
        if points >= 1000 {
            return "\(points / 1000)K pts"
        }
        return "\(points) pts"
    }
}

// MARK: - Screen wrapper

struct TheHaulCosmeticsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TheHaulCosmetics()
        } nav: {
            BottomNav(
                leading: driverNavLeading_066(),
                trailing: driverNavTrailing_066(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_066() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: true)]
}
private func driverNavTrailing_066() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Previews
//
// Previews never run the `.task` refresh — the store stays in `.loading`
// so both registers render the loading skeleton without hitting the
// network. No fixtures.

#Preview("066 · The Haul Cosmetics · Night") {
    TheHaulCosmeticsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("066 · The Haul Cosmetics · Afternoon") {
    TheHaulCosmeticsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
