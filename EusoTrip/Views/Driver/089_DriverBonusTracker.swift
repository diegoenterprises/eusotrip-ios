//
//  089_DriverBonusTracker.swift
//  EusoTrip — Driver · Bonus Tracker (rewards + badges).
//
//  iOS port of the web `frontend/client/src/pages/BonusTracker.tsx`.
//  Reads off the real rewards router:
//    rewards.getSummary    — points / tier / nextTier / lifetimeEarnings
//    rewards.getAvailable  — badges the driver hasn't earned yet
//    rewards.getHistory    — badges already earned
//
//  Note: the web BonusTracker.tsx ships with a broken `(trpc as any).
//  gamification?.getRewards?.useQuery?.()` chain that resolves to
//  `undefined` (no such endpoint exists). The iOS port talks to the
//  REAL endpoints so the screen renders real data. A web-side follow-up
//  to align with the same contract is queued.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

struct RewardsSummary: Decodable, Hashable {
    let points: Int
    let tier: String
    let nextTier: String
    let pointsToNextTier: Int
    let lifetimeEarnings: Int
    let totalEarned: Int
    let redeemed: Int
    let tierProgress: Int?
}

struct RewardBadge: Decodable, Hashable, Identifiable {
    let id: String
    let code: String?
    let name: String
    let description: String?
    let category: String?
    let tier: String?
    let xpValue: Int?
    let isRare: Bool?
    let earned: Bool?
}

struct EarnedBadge: Decodable, Hashable, Identifiable {
    let id: Int
    var stringId: String { String(id) }
    let badgeId: Int?
    let earnedAt: String?
    let badgeName: String?
    let badgeCategory: String?
    let badgeTier: String?
    let xpValue: Int?
}

// MARK: - Screen

struct DriverBonusTrackerScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { BonusTrackerBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: DriverTab.home.label,  systemImage: DriverTab.home.systemImage,  isCurrent: false),
                          NavSlot(label: DriverTab.trips.label, systemImage: DriverTab.trips.systemImage, isCurrent: false)],
                trailing: [NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: false),
                           NavSlot(label: DriverTab.me.label,    systemImage: DriverTab.me.systemImage,     isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct BonusTrackerBody: View {
    @Environment(\.palette) private var palette

    @State private var summary: RewardsSummary?
    @State private var available: [RewardBadge] = []
    @State private var earned: [EarnedBadge] = []
    @State private var loading: Bool = true
    @State private var error: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && summary == nil {
                    LifecycleCard {
                        Text("Loading rewards…")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                } else if let err = error {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    if let s = summary { summaryCard(s) }
                    statsRow
                    if !available.isEmpty {
                        availableSection
                    }
                    if !earned.isEmpty {
                        earnedSection
                    }
                    if available.isEmpty && earned.isEmpty {
                        EusoEmptyState(
                            systemImage: "trophy",
                            title: "No rewards yet",
                            subtitle: "Complete loads and milestones to start earning badges."
                        )
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · BONUS TRACKER")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Rewards & badges")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Points, tier progress, and badges you've earned (or can still chase).")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryCard(_ s: RewardsSummary) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CURRENT TIER").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                        Text(s.tier.uppercased())
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("POINTS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                        Text("\(s.points)")
                            .font(.system(size: 22, weight: .heavy).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                if s.pointsToNextTier > 0 && s.nextTier != s.tier {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Next: \(s.nextTier.uppercased())")
                                .font(EType.caption.weight(.semibold))
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text("\(s.pointsToNextTier) pts to go")
                                .font(EType.caption.monospacedDigit())
                                .foregroundStyle(palette.textTertiary)
                        }
                        let frac = max(0, min(100, s.tierProgress ?? 0))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.bgCard).frame(height: 6)
                                Capsule()
                                    .fill(LinearGradient.diagonal)
                                    .frame(width: CGFloat(frac) / 100 * geo.size.width, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "EARNED",      value: "\(earned.count)",        icon: "checkmark.seal.fill")
            LifecycleStatTile(label: "AVAILABLE",   value: "\(available.count)",     icon: "target")
            LifecycleStatTile(label: "LIFETIME XP", value: "\(summary?.totalEarned ?? 0)", icon: "star.fill")
        }
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("AVAILABLE BADGES")
            ForEach(available) { b in
                LifecycleCard {
                    HStack(spacing: 10) {
                        Image(systemName: categoryIcon(b.category))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(b.name)
                                    .font(EType.body.weight(.bold))
                                    .foregroundStyle(palette.textPrimary)
                                if b.isRare == true {
                                    Text("RARE")
                                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.purple.opacity(0.18)))
                                        .foregroundStyle(Color.purple)
                                }
                                Spacer(minLength: 0)
                                if let xp = b.xpValue, xp > 0 {
                                    Text("+\(xp) XP")
                                        .font(EType.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(palette.textPrimary)
                                }
                            }
                            Text(b.description ?? "")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                if let c = b.category {
                                    capsule(text: c.uppercased(), color: categoryColor(c))
                                }
                                if let t = b.tier {
                                    capsule(text: t.uppercased(), color: tierColor(t))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var earnedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("EARNED BADGES")
            ForEach(earned) { b in
                LifecycleCard(accentGradient: true) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.badgeName ?? "Badge \(b.id)")
                                .font(EType.body.weight(.bold))
                                .foregroundStyle(palette.textPrimary)
                            HStack(spacing: 6) {
                                if let c = b.badgeCategory { capsule(text: c.uppercased(), color: categoryColor(c)) }
                                if let t = b.badgeTier     { capsule(text: t.uppercased(), color: tierColor(t)) }
                                if let xp = b.xpValue, xp > 0 {
                                    Text("+\(xp) XP")
                                        .font(EType.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(palette.textPrimary)
                                }
                            }
                            if let when = b.earnedAt {
                                Text("Earned \(shortDate(when))")
                                    .font(.caption2)
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(palette.textTertiary)
    }

    private func capsule(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private func categoryIcon(_ raw: String?) -> String {
        switch (raw ?? "").lowercased() {
        case "milestone":   return "target"
        case "safety":      return "shield.fill"
        case "referral":    return "person.2.fill"
        case "seasonal":    return "leaf.fill"
        case "performance": return "chart.line.uptrend.xyaxis"
        default:            return "rosette"
        }
    }

    private func categoryColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "milestone":   return .blue
        case "safety":      return .green
        case "referral":    return .purple
        case "seasonal":    return .orange
        case "performance": return .cyan
        default:            return .secondary
        }
    }

    private func tierColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "bronze":   return Color(red: 0.66, green: 0.42, blue: 0.21)
        case "silver":   return Color.gray
        case "gold":     return .yellow
        case "platinum": return .cyan
        case "diamond":  return .purple
        default:         return .secondary
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        return out.string(from: d)
    }

    // MARK: pipeline

    private func loadAll() async {
        loading = true; error = nil
        async let s: Void = loadSummary()
        async let a: Void = loadAvailable()
        async let e: Void = loadEarned()
        _ = await (s, a, e)
        loading = false
    }

    private func loadSummary() async {
        do {
            let s: RewardsSummary = try await EusoTripAPI.shared.queryNoInput("rewards.getSummary")
            summary = s
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadAvailable() async {
        struct In: Encodable { let limit: Int? }
        do {
            let a: [RewardBadge] = try await EusoTripAPI.shared.query(
                "rewards.getAvailable", input: In(limit: 20)
            )
            available = a
        } catch {
            // Best-effort.
        }
    }

    private func loadEarned() async {
        struct In: Encodable { let limit: Int? }
        do {
            let e: [EarnedBadge] = try await EusoTripAPI.shared.query(
                "rewards.getHistory", input: In(limit: 30)
            )
            earned = e
        } catch {
            // Best-effort.
        }
    }
}

#Preview("089 · Bonus · Dark") {
    DriverBonusTrackerScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("089 · Bonus · Light") {
    DriverBonusTrackerScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
