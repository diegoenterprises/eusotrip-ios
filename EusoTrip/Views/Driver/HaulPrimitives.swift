//
//  HaulPrimitives.swift
//  EusoTrip — The Haul (P1) · reusable bespoke gamification primitives.
//
//  P1 foundation per the Design Authority Haul band (SVG 067 Mission /
//  068 Leaderboard / 069 Achievements Wall / 071 Daily Streak; reference
//  ports under "01 Driver/Code/067_DriverHaulMission.swift" etc.). Each
//  primitive is a faithful adaptation of its reference-port composition,
//  re-skinned onto the LIVE design system (eusoCard / LinearGradient /
//  Brand / EType / Space / Radius / palette) and parameterized by a model
//  so the live Haul tabs bind real gamification data. Call sites here are
//  #Preview-only — the shell wires them (PR3).
//
//  Vocabulary law (Trillion-Dollar doctrine): driver-facing copy uses
//  Standing / Recognition / Miles-Earned — never game / level / loot / boss.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Shared meter

/// The canonical Haul progress meter. ProgressBar067 / 069 / 071 were three
/// byte-identical copies across the reference ports — consolidated here.
struct HaulProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textTertiary.opacity(0.18))
                Capsule().fill(LinearGradient.primary)
                    .frame(width: max(height, geo.size.width * max(0, min(fraction, 1))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Season Hero (067)

struct HaulSeasonHeroModel {
    let season: String          // "SEASON 7 · THE HAUL"
    let tier: String            // "STANDING · ROAD CAPTAIN"
    var tierTint: Color = Brand.escort
    let name: String            // "Coast Run season"
    let sub: String             // "ends in 12d · resets Jun 10 · rank 4 of guild"
    let milesLabel: String      // "SEASON MILES"
    let miles: Int
    let milesTarget: Int
    let nextTierLine: String    // "Next Standing: Night Hauler · +3,580 to promote"
    var fraction: Double { Double(miles) / Double(max(1, milesTarget)) }
}

/// The always-visible season/program hero (reference: 067 seasonHero L89-112),
/// re-skinned off the hand-rolled RoundedRectangle + LinearGradient.primary
/// stroke onto eusoCard(.feature) — whose iridescent rim IS the wireframe
/// cardRim, so we don't double-stroke.
struct HaulSeasonHero: View {
    let model: HaulSeasonHeroModel
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(model.season)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(model.tier)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(model.tierTint)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(model.tierTint.opacity(scheme == .dark ? 0.18 : 0.12)))
            }
            Text(model.name)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 8)
            Text(model.sub)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 12)
            HStack {
                Text(model.milesLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(model.miles.formatted()) / \(model.milesTarget.formatted())")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
            HaulProgressBar(fraction: model.fraction).padding(.top, 8)
            Text(model.nextTierLine)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 8)
        }
        .padding(16)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }
}

// MARK: - Tier Ladder (067)

struct HaulTier: Identifiable {
    let id = UUID()
    let name: String
    enum State { case done, current, locked }
    let state: State
}

/// The Standing tier ladder node strip (reference: 067 tierLadder L150-180).
struct HaulTierLadder: View {
    let tiers: [HaulTier]
    var season: String = "SEASON 7"
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STANDING LADDER · \(season)")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            ZStack {
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                    .padding(.horizontal, 28).padding(.bottom, 18)
                HStack(spacing: 0) {
                    ForEach(tiers) { t in
                        VStack(spacing: 8) {
                            ZStack {
                                switch t.state {
                                case .current:
                                    Circle().fill(LinearGradient.diagonal).frame(width: 26, height: 26)
                                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                                 center: .init(x: 0.35, y: 0.30),
                                                                 startRadius: 0, endRadius: 12))
                                        .frame(width: 26, height: 26)
                                case .done:
                                    Circle().fill(LinearGradient.primary).frame(width: 22, height: 22)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                case .locked:
                                    Circle().fill(palette.borderFaint).frame(width: 20, height: 20)
                                        .overlay(Circle().stroke(palette.borderFaint, lineWidth: 1))
                                }
                            }
                            Text(t.name)
                                .font(.system(size: 8, weight: t.state == .current ? .heavy : .bold)).tracking(0.2)
                                .foregroundStyle(t.state == .current ? palette.textPrimary
                                                 : (t.state == .done ? palette.textSecondary : palette.textTertiary))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(height: 72).frame(maxWidth: .infinity)
            .eusoCard(radius: Radius.lg, intensity: .standard)
        }
    }
}

// MARK: - Mission Row (067)

struct HaulMissionRowModel: Identifiable {
    let id: Int
    let title: String
    let sub: String
    let reward: String          // "+450 Miles"
    let progress: Double
    let progressLabel: String   // "4 / 5" or "READY"
    let tint: Color
    let ready: Bool
}

/// A single weekly-mission row (reference: 067 missionList row L114-148).
/// The Missions tab stacks these inside an eusoCard(.standard) with faint
/// dividers — this is just the row content.
struct HaulMissionRow: View {
    let m: HaulMissionRowModel
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(m.tint.opacity(scheme == .dark ? 0.18 : 0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: m.ready ? "checkmark" : "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(m.tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(m.sub).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                HaulProgressBar(fraction: m.progress)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(m.progressLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(m.ready ? Brand.success : m.tint)
                Text(m.reward)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Previews (067 family)

#Preview("Haul · Season Hero + Ladder · Dark") {
    ScrollView {
        VStack(spacing: 14) {
            HaulSeasonHero(model: .init(
                season: "SEASON 7 · THE HAUL", tier: "STANDING · ROAD CAPTAIN",
                name: "Coast Run season", sub: "ends in 12d · resets Jun 10 · rank 4 of guild",
                milesLabel: "SEASON MILES", miles: 8420, milesTarget: 12000,
                nextTierLine: "Next Standing: Night Hauler · +3,580 to promote"))
            HaulTierLadder(tiers: [
                .init(name: "Rookie", state: .done), .init(name: "Hauler", state: .done),
                .init(name: "Road Capt", state: .current), .init(name: "Night H.", state: .locked),
                .init(name: "Legend", state: .locked),
            ])
            VStack(spacing: 0) {
                HaulMissionRow(m: .init(id: 1, title: "Five clean deliveries", sub: "No defects · no detention",
                                        reward: "+450 Miles", progress: 0.8, progressLabel: "4 / 5", tint: Brand.info, ready: false))
                Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                HaulMissionRow(m: .init(id: 2, title: "On-time streak ×7", sub: "7 consecutive on-time PODs",
                                        reward: "+300 Miles", progress: 1.0, progressLabel: "READY", tint: Brand.success, ready: true))
            }
            .padding(.horizontal, 16)
            .eusoCard(radius: Radius.lg, intensity: .standard)
        }
        .padding(16)
    }
    .environment(\.palette, Theme.dark)
}

// MARK: - Rank Hero + Scope Selector (068)

struct HaulRankStat: Identifiable {
    let id = UUID()
    let label: String           // "PERCENTILE"
    let value: String           // "TOP 1%"
}

struct HaulRankHeroModel {
    let scopeLabel: String      // "YOUR RANK · GUILD AURORA"
    let rank: Int               // 4
    let total: Int              // 1284
    let deltaLine: String?      // "UP 3 THIS WK"
    let stats: [HaulRankStat]   // PERCENTILE / SEASON POINTS
    let gapLine: String         // "240 pts from #3 · 2 clean runs"
}

/// The leaderboard hero (reference: 068 rankHero) — giant gradient rank
/// numeral + delta capsule + offset stat block + gap line, on eusoCard(.feature).
struct HaulRankHero: View {
    let model: HaulRankHeroModel
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(model.scopeLabel)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                if let delta = model.deltaLine {
                    Text(delta)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.success.opacity(scheme == .dark ? 0.18 : 0.12)))
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("#\(model.rank)")
                        .font(.system(size: 46, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.primary)
                    Text("of \(model.total.formatted())")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(model.stats) { s in
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(s.label)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                                .foregroundStyle(palette.textTertiary)
                            Text(s.value)
                                .font(EType.mono(.caption)).bold()
                                .foregroundStyle(palette.textPrimary)
                        }
                    }
                }
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            Text(model.gapLine)
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
        }
        .padding(16)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }
}

enum HaulScope: String, CaseIterable, Identifiable { case guild = "GUILD", region = "REGION", global = "GLOBAL"
    var id: String { rawValue }
}

/// GUILD / REGION / GLOBAL segmented scope selector (reference: 068 scopeSelector).
struct HaulScopeSelector: View {
    @Binding var scope: HaulScope
    var onChange: (HaulScope) -> Void = { _ in }
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 4) {
            ForEach(HaulScope.allCases) { s in
                let on = s == scope
                Text(s.rawValue)
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(on ? .white : palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        Group {
                            if on { RoundedRectangle(cornerRadius: 13).fill(LinearGradient.diagonal) }
                            else {
                                RoundedRectangle(cornerRadius: 13).fill(palette.bgCard)
                                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(palette.borderFaint, lineWidth: 1))
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !on else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { scope = s }
                        onChange(s)
                    }
            }
        }
    }
}

// MARK: - Standing Row (068)

struct HaulStandingRowModel: Identifiable {
    let id: Int
    let rank: Int
    let name: String
    let lane: String            // mono sub, e.g. "Coast lane · TX"
    let points: String          // "9,840"
    let isMe: Bool
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
    }
}

/// A single leaderboard standing row (reference: 068 standingsCard row).
/// The self row is washed in the brand diagonal; top-3 get a tinted medal disc.
struct HaulStandingRow: View {
    let m: HaulStandingRowModel
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    private var medalTint: Color {
        switch m.rank { case 1: return Brand.warning; case 2: return palette.textSecondary; case 3: return Brand.escort; default: return palette.textTertiary }
    }
    var body: some View {
        HStack(spacing: 12) {
            Text("\(m.rank)")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(m.rank <= 3 ? medalTint : palette.textTertiary)
                .frame(width: 26, alignment: .center)
            ZStack {
                Circle().fill(medalTint.opacity(scheme == .dark ? 0.20 : 0.14))
                Text(m.initials)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(medalTint)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                if !m.lane.isEmpty {
                    Text(m.lane).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(m.points)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(m.isMe
                    ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.10))
                    : AnyShapeStyle(Color.clear))
        )
    }
}

// MARK: - Collection Hero + Badge Grid (069)

struct HaulRarity: Identifiable {
    let id = UUID()
    let label: String           // "Common"
    let count: String           // "21"
    let dot: Color
}

struct HaulCollectionHeroModel {
    let earned: Int
    let total: Int
    let rarities: [HaulRarity]
    var fraction: Double { Double(earned) / Double(max(1, total)) }
}

/// Collection-progress hero (reference: 069 collectionHero) — giant gradient
/// fraction + rarity legend + meter, on eusoCard(.feature).
struct HaulCollectionHero: View {
    let model: HaulCollectionHeroModel
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RECOGNITION PROGRESS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(model.earned)")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.primary)
                    Text("/ \(model.total)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.rarities) { r in
                        HStack(spacing: 6) {
                            Circle().fill(r.dot).frame(width: 8, height: 8)
                            Text(r.label).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 0)
                            Text(r.count).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
                .frame(width: 150)
            }
            Text("badges unlocked").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            HaulProgressBar(fraction: model.fraction)
        }
        .padding(16)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }
}

struct HaulBadge: Identifiable {
    let id = UUID()
    let name: String
    let state: String           // earned condition or unlock condition
    let tint: Color
    let earned: Bool
}

/// 3-column badge grid (reference: 069 badgeGrid). Earned = tinted medallion +
/// star; locked = faint + lock. Each cell on eusoCard(.whisper).
struct HaulBadgeGrid: View {
    let badges: [HaulBadge]
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    var body: some View {
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(badges) { b in
                VStack(spacing: 6) {
                    ZStack {
                        if b.earned {
                            Circle().fill(b.tint.opacity(scheme == .dark ? 0.18 : 0.12))
                            Image(systemName: "star.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(b.tint)
                        } else {
                            Circle().fill(palette.borderFaint).overlay(Circle().stroke(palette.borderFaint, lineWidth: 1))
                            Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textTertiary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    Text(b.name).font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary).multilineTextAlignment(.center).lineLimit(2)
                    Text(b.state).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center).lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 118)
                .padding(.vertical, 10).padding(.horizontal, 6)
                .eusoCard(radius: Radius.md, intensity: .whisper)
            }
        }
    }
}

// MARK: - Streak Ring (071)

struct HaulStreakModel {
    let days: Int               // current streak, centered in the ring
    let goal: Int               // ring target
    let week: [Bool]            // 7 dots, true = hit
    let freezeTokens: Int       // freeze tokens remaining
    var fraction: Double { Double(days) / Double(max(1, goal)) }
}

/// The streak hero (reference: 071 StreakRing071 + week strip + freeze strip):
/// a banded progress ring with the day count centered, a 7-day dot row, and a
/// freeze-token chip. The ring is drawn bespoke (trim) for self-containment.
struct HaulStreakRing: View {
    let model: HaulStreakModel
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(palette.textTertiary.opacity(0.18), lineWidth: 10)
                Circle().trim(from: 0, to: max(0.001, min(model.fraction, 1)))
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(model.days)")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    Text("DAY STREAK")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .frame(width: 132, height: 132)
            HStack(spacing: 8) {
                ForEach(Array(model.week.enumerated()), id: \.offset) { _, hit in
                    Circle()
                        .fill(hit ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary.opacity(0.2)))
                        .frame(width: 12, height: 12)
                }
            }
            if model.freezeTokens > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "snowflake").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.info)
                    Text("\(model.freezeTokens) freeze \(model.freezeTokens == 1 ? "token" : "tokens")")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Brand.info.opacity(scheme == .dark ? 0.16 : 0.10)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .eusoCard(radius: Radius.lg, intensity: .standard)
    }
}

// MARK: - Previews (068/069/071 family)

#Preview("Haul · Rank + Collection + Streak · Dark") {
    ScrollView {
        VStack(spacing: 14) {
            HaulRankHero(model: .init(
                scopeLabel: "YOUR RANK · GUILD AURORA", rank: 4, total: 1284, deltaLine: "UP 3 THIS WK",
                stats: [.init(label: "PERCENTILE", value: "TOP 1%"), .init(label: "SEASON POINTS", value: "9,840")],
                gapLine: "240 pts from #3 · 2 clean runs"))
            HaulScopeSelector(scope: .constant(.guild))
            HaulCollectionHero(model: .init(earned: 37, total: 60, rarities: [
                .init(label: "Common", count: "21", dot: Color.gray),
                .init(label: "Rare", count: "12", dot: Brand.info),
                .init(label: "Legendary", count: "4", dot: Brand.warning),
            ]))
            HaulStreakRing(model: .init(days: 23, goal: 30, week: [true, true, true, true, false, true, true], freezeTokens: 2))
        }
        .padding(16)
    }
    .environment(\.palette, Theme.dark)
}
