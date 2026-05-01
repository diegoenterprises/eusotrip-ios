//
//  062_TheHaulBadges.swift
//  EusoTrip 2027 UI — Wave 7 (driver · The Haul · badges gallery)
//
//  Screen 062 · The Haul · Badges — the dedicated badge gallery that
//  deepens the 060 "Badges" preview row and the Me → Badges sub-route
//  (`MeBadgesView`). This surface is the full-screen workspace where
//  the driver can:
//
//    • Scan their full badge collection in a 2-column grid.
//    • Filter by tier (All / Bronze / Silver / Gold / Platinum) via
//      the gradient chip rail.
//    • Toggle "Earned only" to hide locked tiles while they plan the
//      next pursuit.
//    • Open any tile to read the full description + earned date in a
//      brand-gradient detail sheet.
//    • Pull-to-refresh after a mission clear posts a new award.
//
//  Cohort B — fully dynamic from day 1
//  (SKILL.md §3 "no-mock" pledge · 2027 motivation "no fake data"):
//
//    • Every badge on this surface originates from `gamification.getBadges`
//      via the canonical `BadgesStore` (§16 the-haul slice · MCP-verified
//      at `frontend/server/routers/gamification.ts:528`). Zero seeded
//      badge names, icons, tiers, or earned dates anywhere in the file.
//    • The summary card reads its counts off `badgesStore.items` — never
//      a hard-coded "12 of 50" literal.
//    • When the server returns an empty roster the screen renders the
//      canonical `EusoEmptyState` primitive. No placeholder tiles.
//    • The stats card derives "Next tier" by folding the live tier
//      distribution, not a baked-in roadmap.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal everywhere brand accent is needed —
//         filter chip selection, earned badge glyph ring, stats card
//         accent. Zero `Brand.info` / `Brand.blue` fills.
//    §3   Numbers-first — "12 EARNED / 34 TOTAL" is the primary visual
//         anchor of the stats card. Copy is demoted to uppercase caps.
//    §4   Tokenized spacing (`Space.sN`), radii (`Radius.sm/md/lg/xl`),
//         type (`EType.*`).
//    §5   Palette semantic — `palette.textPrimary/Secondary/Tertiary`,
//         `palette.bgCard/bgPage`, `palette.borderFaint`. Never hard-coded
//         `Color.gray` / `Color.black` / `Color.white` (except shadow
//         opacity + CTA fg, which remain `.white` by doctrine).
//    §7   Ternary ShapeStyle expressions wrap in `AnyShapeStyle`.
//    §10  Previews compile in isolation — unauthenticated session hydrates
//         the live store to `.error` (unauthenticated) or `.empty` so the
//         preview renders the branded empty path without the network.
//

import SwiftUI

// MARK: - Screen

struct TheHaulBadges: View {
    @Environment(\.palette) var palette

    @StateObject private var store = BadgesStore()

    /// Active tier filter. `nil` = "All tiers" (no filter).
    @State private var tier: BadgeTier? = nil

    /// When true, hide locked badges (those with `earnedAt == nil`).
    @State private var earnedOnly: Bool = false

    /// Badge selected for the detail sheet.
    @State private var detailBadge: DriverBadge? = nil

    /// Transient toast (e.g. refresh error surfaced from the store).
    @State private var toast: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    private let cols = [GridItem(.flexible(), spacing: Space.s3),
                        GridItem(.flexible(), spacing: Space.s3)]

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Space.s5) {
                    header
                    statsCard
                    filterRail
                    earnedToggleRow
                    gridOrEmpty
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s8)
            }
            .refreshable {
                await store.refresh()
                if let e = store.lastError { showToast(e.localizedDescription) }
            }
            .task { await store.refresh() }

            if let toast {
                toastBanner(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, Space.s3)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
        .sheet(item: $detailBadge) { b in
            BadgeDetailSheet(badge: b)
                .environment(\.palette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .eusoCloseX()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Badges")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Trophy case · seasons and streaks")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: .idle, diameter: 40)
        }
    }

    private var statsCard: some View {
        let earned = store.items.filter { $0.earnedAt != nil }.count
        let total = store.items.count
        let nextTierCopy = nextTierHint()

        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("\(earned)")
                    .font(EType.display)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("EARNED")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(total) TOTAL")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
            }

            progressBar(earned: earned, total: total)

            if let hint = nextTierCopy {
                HStack(spacing: Space.s2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(hint)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func progressBar(earned: Int, total: Int) -> some View {
        let pct: Double = total == 0 ? 0 : Double(earned) / Double(total)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.pill)
                    .fill(palette.tintNeutral)
                RoundedRectangle(cornerRadius: Radius.pill)
                    .fill(LinearGradient.diagonal)
                    .frame(width: max(6, geo.size.width * pct))
            }
        }
        .frame(height: 8)
    }

    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                chip(label: "All", active: tier == nil) { tier = nil }
                ForEach(BadgeTier.allCases) { t in
                    chip(label: t.label, active: tier == t) {
                        tier = (tier == t) ? nil : t
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(EType.micro)
                .tracking(0.6)
                .foregroundStyle(active ? Color.white : palette.textSecondary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(
                    Capsule()
                        .fill(active
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.tintNeutral))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(active ? Color.clear : palette.borderFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var earnedToggleRow: some View {
        HStack {
            Text("Earned only")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Toggle("", isOn: $earnedOnly)
                .labelsHidden()
                .toggleStyle(GradientToggleStyle())
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
    }

    @ViewBuilder
    private var gridOrEmpty: some View {
        switch store.state {
        case .loading:
            loadingSkeleton
        case .empty:
            EusoEmptyState(
                systemImage: "rosette",
                title: "No badges yet",
                subtitle: "First 100 loads, safety streaks, and MPG wins all unlock here."
            )
            .padding(.top, Space.s4)
        case .error(let e):
            EusoEmptyState(
                systemImage: "exclamationmark.triangle",
                title: "Couldn't load badges",
                subtitle: e.localizedDescription
            )
            .padding(.top, Space.s4)
        case .loaded(let items):
            let rows = filtered(items)
            if rows.isEmpty {
                EusoEmptyState(
                    systemImage: "line.3.horizontal.decrease.circle",
                    title: "Nothing matches this filter",
                    subtitle: "Clear the tier filter or turn off \"Earned only\"."
                )
                .padding(.top, Space.s4)
            } else {
                LazyVGrid(columns: cols, spacing: Space.s3) {
                    ForEach(rows) { b in
                        badgeTile(b)
                            .onTapGesture { detailBadge = b }
                    }
                }
            }
        }
    }

    private var loadingSkeleton: some View {
        LazyVGrid(columns: cols, spacing: Space.s3) {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Space.s2) {
                    Circle()
                        .fill(palette.tintNeutral)
                        .frame(width: 56, height: 56)
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(palette.tintNeutral)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(palette.tintNeutral.opacity(0.6))
                        .frame(height: 10)
                }
                .padding(Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .eusoCard(radius: Radius.lg)
                .redacted(reason: .placeholder)
            }
        }
    }

    private func badgeTile(_ b: DriverBadge) -> some View {
        let earned = b.earnedAt != nil
        return VStack(alignment: .leading, spacing: Space.s2) {
            ZStack {
                Circle()
                    .fill(earned
                          ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.22))
                          : AnyShapeStyle(palette.tintNeutral))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Circle()
                            .strokeBorder(earned
                                          ? AnyShapeStyle(LinearGradient.diagonal)
                                          : AnyShapeStyle(palette.borderFaint),
                                          lineWidth: earned ? 1.5 : 1)
                    )
                Image(systemName: b.iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(earned
                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                     : AnyShapeStyle(palette.textTertiary))
            }

            Text(b.name)
                .font(EType.bodyStrong)
                .foregroundStyle(earned ? palette.textPrimary : palette.textSecondary)
                .lineLimit(1)

            if let tier = b.tier, !tier.isEmpty {
                Text(tier.uppercased())
                    .font(EType.micro)
                    .tracking(1.2)
                    .foregroundStyle(earned ? palette.textSecondary : palette.textTertiary)
            }

            if let desc = b.description {
                Text(desc)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
        .opacity(earned ? 1 : 0.72)
        .contentShape(Rectangle())
    }

    private func toastBanner(_ text: String) -> some View {
        Text(text)
            .font(EType.bodyStrong)
            .foregroundStyle(Color.white)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.pill)
                    .fill(LinearGradient.diagonal)
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    // MARK: Data

    private func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    private func filtered(_ all: [DriverBadge]) -> [DriverBadge] {
        var rows = all
        if let t = tier {
            rows = rows.filter { ($0.tier ?? "").lowercased() == t.key }
        }
        if earnedOnly {
            rows = rows.filter { $0.earnedAt != nil }
        }
        return rows
    }

    private func nextTierHint() -> String? {
        // Count earned per tier and call out the tier closest to completion.
        let grouped = Dictionary(grouping: store.items, by: { ($0.tier ?? "").lowercased() })
        var best: (tier: String, pct: Double, earned: Int, total: Int)? = nil
        for (k, arr) in grouped where !k.isEmpty && k != "platinum" {
            let earned = arr.filter { $0.earnedAt != nil }.count
            let total = arr.count
            guard total > earned, total > 0 else { continue }
            let pct = Double(earned) / Double(total)
            if best == nil || pct > best!.pct {
                best = (k, pct, earned, total)
            }
        }
        if let b = best {
            let remain = b.total - b.earned
            return "\(remain) more \(b.tier.capitalized) badge\(remain == 1 ? "" : "s") to clear this tier."
        }
        return nil
    }
}

// MARK: - BadgeTier

enum BadgeTier: String, CaseIterable, Identifiable {
    case bronze, silver, gold, platinum
    var id: String { rawValue }
    var key: String { rawValue }
    var label: String {
        switch self {
        case .bronze:   return "Bronze"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        case .platinum: return "Platinum"
        }
    }
}

// MARK: - Detail sheet

private struct BadgeDetailSheet: View {
    let badge: DriverBadge
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Space.s4) {
            IridescentHairline()
                .frame(width: 48)
                .padding(.top, Space.s3)

            glyph

            Text(badge.name)
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)

            if let tier = badge.tier, !tier.isEmpty {
                Text(tier.uppercased())
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(LinearGradient.diagonal)
            }

            if let desc = badge.description {
                Text(desc)
                    .font(EType.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s4)
            }

            statusRow

            Spacer(minLength: Space.s2)

            CTAButton(title: "Close") { dismiss() }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s5)
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgPage.ignoresSafeArea())
    }

    private var glyph: some View {
        let earned = badge.earnedAt != nil
        return ZStack {
            Circle()
                .fill(earned
                      ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.25))
                      : AnyShapeStyle(palette.tintNeutral))
                .frame(width: 108, height: 108)
                .overlay(
                    Circle()
                        .strokeBorder(earned
                                      ? AnyShapeStyle(LinearGradient.diagonal)
                                      : AnyShapeStyle(palette.borderFaint),
                                      lineWidth: earned ? 2 : 1)
                )
            Image(systemName: badge.iconName)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(earned
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textTertiary))
        }
        .padding(.top, Space.s3)
    }

    private var statusRow: some View {
        HStack(spacing: Space.s2) {
            if let earnedAt = badge.earnedAt, let pretty = prettyDate(earnedAt) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Earned \(pretty)")
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Locked — keep hauling")
                    .font(EType.micro)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(
            Capsule()
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func prettyDate(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let df = DateFormatter()
            df.dateFormat = "MMM d, yyyy"
            return df.string(from: d)
        }
        return nil
    }
}

// MARK: - Screen wrapper

struct TheHaulBadgesScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TheHaulBadges()
        } nav: {
            BottomNav(
                leading: driverNavLeading_062(),
                trailing: driverNavTrailing_062(),
                orbState: .idle
            )
        }
    }
}

// 062 ships the Haul-tab custom variant (Haul current, frozen per
// [feedback_bottom_nav_frozen]). iOS file `TheHaulBadges` but PNG
// slot rebranded to "Training and Certs" — same iOS-vs-PNG mismatch
// as 057-061, out of safe-mode scope. Only SF Symbol naming polish.
private func driverNavLeading_062() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy",     isCurrent: true)]
}
private func driverNavTrailing_062() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

// MARK: - Previews
//
// Both previews render the production path — live store, no fixtures.
// An unauthenticated `EusoTripSession()` resolves the store to `.error`
// or `.empty` deterministically without hitting the network, so the
// preview renders the branded empty path. A real signed-in driver with
// an earned badge roster will see the live tiles on device.

#Preview("062 · The Haul Badges · Night · Empty / Live store") {
    TheHaulBadgesScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("062 · The Haul Badges · Afternoon · Empty / Live store") {
    TheHaulBadgesScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
