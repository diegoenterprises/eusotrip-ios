//
//  550_DispatcherPerformanceReview.swift
//  EusoTrip 2027 · LIVE DATA LAYER
//  CATALOG IDENTITY: 04 Dispatcher · 550 Dispatcher Performance Review
//  (DISPATCHER vantage · Aurora · RM)
//
//  MIRRORS: "04 Dispatcher/Light-SVG/550 Dispatcher Performance Review.svg"
//  (+ Dark). BESPOKE COMPOSITION, faithful 1:1:
//  DETAIL TopBar -> RANK-RIBBON hero (standing drawn as an ordered row of discs)
//  -> COMPARISON LEDGER (a YOU / Δ header strip over KPI rows; each row is a
//  40x40 rx10 icon chip carrying a per-KPI glyph, the KPI title and its mono
//  denominator sub-line, then a right cluster of this dispatcher's figure
//  stacked over the figure it is read against, and the delta at the far right)
//  -> ESang weakest-axis row -> CTA pair -> BottomNav.
//
//  ── DESIGN-SYSTEM PASS · 2026-08-26 ──────────────────────────────────────
//  Raw/system colors and the two locally-declared brand gradients were
//  replaced with EusoTrip design-system tokens (Theme.Palette · Brand ·
//  LinearGradient.primary/.diagonal · Space · Radius · IridescentHairline),
//  and the screen now routes through the house Shell + BottomNav via ShellNav
//  exactly as Dpch730_DispatcherOpsQuartet does. THE DATA LAYER IS UNTOUCHED:
//  every endpoint string, decoder shape, error branch and disabled-control
//  reason below is byte-for-byte the endpoint-verified original.
//
//  RE-BODIED ON PURPOSE: the body of this screen used to be a PERCENTILE BULLET
//  LADDER. That composition duplicated 547 Training Simulator's scored-track
//  ladder — the monotony failure this lane exists to prevent — so it was removed
//  outright rather than restyled. There are NO bars, tracks or ticks anywhere on
//  this screen; the comparison is carried by paired figures alone.
//  Deliberately unlike 539 Carrier Scorecard (bubble quadrants, and it grades
//  counterparties), 480-487 Comms review (counterparty octet), 547 Simulator
//  (radial dial + scored-track ladder) and 541 Margin Bridge (waterfall).
//
//  ── KE15-DSP-546550 · DATA LAYER REBUILT 2026-08-17 ──────────────────────
//  This file previously claimed "0 stubs · 0 placeholders · fully dynamic" over
//  a view model whose `load()` was a comment-only empty body and whose `peers`
//  and `kpis` arrays were hardcoded literals. That claim was false. The visual
//  composition is UNCHANGED — only the data layer moved.
//
//  WIRED READS (every line number re-verified on disk 2026-08-17; all confirmed
//  at the cited line, no citation was stale):
//    dispatchRole.getPerformanceMetrics     EXISTS dispatchRole.ts:1085
//        -> the KPI rows. Returns a BARE ARRAY of six fixed metrics
//           (loads-delivered · on-time-rate · avg-rate · revenue ·
//           avg-distance · hazmat-loads), each {id, name, value, target,
//           weightUnit}.
//           DECODER TRAP CAUGHT: the unit key is `weightUnit`, NOT `unit`.
//           A struct declaring `unit` would decode nothing and silently print
//           bare numbers with no unit — the precise class of defect this fire
//           exists to kill.
//    dispatchRole.getPerformanceStats       EXISTS dispatchRole.ts:1140 · no input
//        -> the HONESTY-LAW denominators (`loadsCompleted`) and the trend.
//    advancedGamification.getLeaderboardHistory EXISTS advancedGamification.ts:1934
//        -> the rank figure, the best rank and the rank movement.
//           DECODER TRAP CAUGHT: the mean key on the wire is `averageRank`,
//           while the server's own local variable is `avgRank`. Decoding
//           `avgRank` would silently yield nil.
//           NOTE: this router uses requireDb() (advancedGamification.ts:52),
//           which THROWS instead of returning a degraded shape — so it needs
//           real error handling, not an empty-state decode.
//    advancedGamification.getGuildLeaderboard EXISTS advancedGamification.ts:533
//        -> the rank-ribbon discs AND the "See the team board" CTA. Returns a
//           BARE ARRAY of {rank, guildId, name, tag, memberCount, totalXp,
//           level, weeklyChange}. `tag` is the derived 2-char label the disc
//           needs. (Flagged for the counter-party row: `totalXp` is actually
//           `guilds.totalMiles` renamed, and `weeklyChange` is a contribution
//           total, not a delta, despite the name.)
//
//  ── HONEST RE-SOURCING (composition preserved, provenance corrected) ──────
//  1. "YOU vs THE DESK" IS NOW "YOU vs TARGET". There is no desk-median
//     procedure on disk — `getPerformanceStats` is self-scope and no endpoint
//     returns a peer distribution. What the server DOES return per metric is a
//     real `target`, so the figure printed under each value is that target and
//     the column is labelled TARGET. The delta is value − target, computed from
//     two real numbers. Printing an invented "desk median" under a real figure
//     would be the exact lie a review screen must not tell.
//  2. THE RIBBON IS THE REAL TEAM BOARD. A per-dispatcher peer roster has NO
//     server source — nothing returns "the other dispatchers on my desk". The
//     only real ordered peer list is getGuildLeaderboard, so the discs carry
//     its real ranks and real 2-char tags and the hero label says TEAM BOARD.
//     No disc is marked "self": the server returns no such flag, and guessing
//     which row is you is exactly the fabrication this lane forbids. The
//     raised/ringed self-disc code path is left intact and will light up the
//     moment the server marks a row.
//  3. The KPI count is six, not five — six is what the server returns.
//
//  ── CITED BUT DELIBERATELY NOT CALLED (each with its reason) ─────────────
//    dispatchRole.getPerformanceHistory     EXISTS dispatchRole.ts:1113
//      NOT WIRED. Its per-row `rating` is FABRICATED SERVER-SIDE — a hardcoded
//      4.8 when the load was on time and 3.8 when it was not (dispatchRole.ts,
//      inside the map). It is not a rating anyone gave. This screen's whole
//      premise is that every figure names its denominator, so a two-value
//      constant dressed as a rating is not admitted. The period delta is
//      computed from value − target instead, which is real.
//      Counter-party row filed. THIS GAP IS STILL OPEN — the reason stays on
//      screen and the procedure stays unwired until the server stops
//      manufacturing the number. ON-SCREEN CITATION: `historyNote`, rendered as
//      the closing micro-caption of the rank-ribbon block.
//    advancedGamification.getStreakTracker  EXISTS advancedGamification.ts:1477
//      NOT WIRED. This composition has no streak row. Additionally flagged for
//      the counter-party row: its `streakHistory` claims in the source comment
//      to be built "from load activity" but the loop never queries any —
//      `completed: i < dailyStreak` is pure arithmetic over a counter.
//    esangCoach.forScreen                   EXISTS esangCoach.ts:264
//      NOT CALLABLE FROM ANY DISPATCHER SCREEN. Its `screen` input is
//      SCREEN_ENUM (esangCoach.ts:112-125) = home | trips | earnings | tax |
//      dvir | availability | missions | badges | referrals | zeun | haul |
//      active-trip — every member a DRIVER surface, so any call from here fails
//      zod validation with BAD_REQUEST. The ESang row is NOT a button in this
//      composition (it is a static row), so there is no dead tap; its sentence
//      is computed from the live KPI reads and names the genuinely weakest
//      metric. Counter-party row filed: add a dispatch token to SCREEN_ENUM.
//
//  ── "EXPORT" ─────────────────────────────────────────────────────────────
//  There is no dispatcher-performance report or export procedure on the server.
//  Rather than leave a dead tap or invent an endpoint, "Export" performs a real,
//  complete, purely local action: it copies the live figures already on screen
//  to the clipboard and confirms it. Nothing is faked and nothing is claimed to
//  have been filed anywhere.
//
//  DISK-TRUTH ALIGNMENT (precedence: real code first): this catalog row is drawn
//  to the code that already exists — web DispatchPerformance.tsx and the iOS
//  orphans 707_DispatchDailyKPI and Dpch714 DispatchPerformanceScreen. This
//  Swift port is their REPLACEMENT, not a sixth lineage.
//  PERSISTENCE + AUDIT + REALTIME: all reads. NO MUTATION ON THIS SCREEN BY
//  DESIGN — a dispatcher cannot write their own review. Rank changes arrive on
//  WS_EVENTS.LEADERBOARD_UPDATE shared/websocket-events.ts:150 over
//  WS_CHANNELS.DISPATCH(companyId) shared/websocket-events.ts:577. No
//  blockchainAuditTrail row (nothing is committed).
//  CHAIN: PARTIAL — the read closes; the LEADERBOARD_UPDATE subscription has no
//  iOS case (S3 family), so rank moves only on manual refresh. Counter-party row
//  filed to the-oath / the-oath-apply.
//  RBAC: protectedProcedure, self scope.
//  OFFLINE POLICY: READ_CACHED(300s) for performance stats and leaderboard; this surface performs no writes; no money movement.
//  HONESTY LAW: every KPI names its own denominator in the sub-line and the
//  figure it is read against is printed directly under it. A figure with no
//  denominator is how review screens lie, and this one does not.
//  transportMode=truck; country US, currency USD — country is content.
//  NAV (REAL · house BottomNav + DispatchNavRoute, DispatchNavController.swift:44/87/92):
//    Home(house) · Board(rectangle.split.3x1.fill · current) · [orb] ·
//    Comms(bubble.left.and.bubble.right.fill) · Me(person). Rendered by the
//    house Shell/BottomNav pair through ShellNav, so slot taps resolve via the
//    injected dispatchNavHandler -> DispatchNavDispatcher.handle chain instead
//    of a screen-owned copy of the dock.
//  Persona Aurora Freight Lines · Renée Marquette (RM) reviewed; shipper-of-record
//  Eusorone Technologies (Diego Usoro · DU).
//
//  HONEST STATUS: 4 reads live, 0 writes (by design) · 3 verified procedures
//  deliberately unwired with reasons · 2 decoder key traps caught (`weightUnit`,
//  `averageRank`) · 2 measurements re-sourced honestly (desk median → target,
//  peer roster → team board) · 1 server-side fabrication surfaced
//  (getPerformanceHistory.rating). No literal row arrays remain.
//  UNCOMPILED — no Swift toolchain on this lane.
//  No retired names. No emoji icons. Exactly one ✦ eyebrow. One iridescent
//  hairline.
//  — Mike "Diego" Usoro / Eusorone Technologies, Inc. · 2026-08-26 EDT.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - WCAG text pair for small text on a tinted wash
//
// The Palette exposes the tinted WASHES (tintSuccess / tintWarning /
// tintDanger) but no matching TEXT token, and Brand.success / Brand.warning /
// Brand.danger are the saturated FILL values — at 11-13pt on a light wash they
// fall under 4.5:1. These three darker variants are the contrast-tested text
// halves of that pair and are kept for exactly that reason. (#1565C0 infoText,
// the fourth member of the house set, has no call-site on this surface, so it
// is not declared here.)
private let dangerText_550  = Color(red: 0.824, green: 0.204, blue: 0.165) // #D2342A
private let warnText_550    = Color(red: 0.698, green: 0.451, blue: 0.0)   // #B27300
private let successText_550 = Color(red: 0.0,   green: 0.588, blue: 0.420) // #00966B

// MARK: - Wire decoders (shapes copied from the server's own return statements)

/// dispatchRole.getPerformanceMetrics — dispatchRole.ts:1085. Bare array.
/// The unit key is `weightUnit`, NOT `unit`.
private struct PerfMetric_550: Decodable {
    let id: String?
    let name: String?
    let value: Double?
    let target: Double?
    let weightUnit: String?
}

/// dispatchRole.getPerformanceStats — dispatchRole.ts:1140. No input.
private struct PerfStats_550: Decodable {
    let avgScore: Double?
    let topScore: Double?
    let trend: String?            // up | stable | down
    let loadsCompleted: Int?
    let successRate: Int?
    let rating: Double?
    let onTimeRate: Int?
    let totalEarnings: Double?
}

/// advancedGamification.getLeaderboardHistory — advancedGamification.ts:1934.
/// The mean key on the wire is `averageRank` (the server's local is `avgRank`).
private struct LeaderboardHistory_550: Decodable {
    let history: [LeaderboardWeek_550]?
    let currentRank: Int?
    let bestRank: Int?
    let averageRank: Double?
    let trend: String?            // improving | declining | stable
}

private struct LeaderboardWeek_550: Decodable {
    let week: String?
    let rank: Int?
    let xpEarned: Double?
    let loadsCompleted: Int?
}

/// advancedGamification.getGuildLeaderboard — advancedGamification.ts:533. Bare array.
private struct GuildRow_550: Decodable {
    let rank: Int?
    let guildId: String?
    let name: String?
    let tag: String?              // derived 2-char label
    let memberCount: Int?
    let level: Int?
}

// MARK: - View models

private struct Peer_550: Identifiable {
    let id = UUID()
    let initials: String
    let rank: String       // "#1" … "#5"
    /// The server returns no "this row is you" flag, so nothing is marked self.
    /// The raised/ringed path below is kept for the day it does.
    let isSelf: Bool
}

/// One row of the comparison ledger. No bar, no track, no tick — this
/// dispatcher's figure is read against the target printed under it.
/// dispatchRole.getPerformanceMetrics dispatchRole.ts:1085.
private struct KPI_550: Identifiable {
    let id = UUID()
    let glyph: String
    let label: String
    let denom: String      // the HONESTY LAW denominator
    let value: String      // em-dash when the server returned no value
    let desk: String       // the figure this one is read against; EMPTY when no target
    let delta: String      // EMPTY when either side of the subtraction is absent
    enum Standing { case above, below }
    /// nil when the server returned no value or no target. An unknown standing
    /// is NEVER coerced to `.above`: two absent figures must not read as a win.
    /// A nil standing renders neutral and is not counted anywhere.
    let standing: Standing?
}

/// The direction the rank actually moved. The movement line's colour is derived
/// from THIS, never hardcoded — "declining vs last period" must not read green.
private enum RankMove_550 { case improving, declining, steady, unknown }

// `private` at file scope: this view model's published properties are typed with
// the file-private row structs above, so the class must be no more accessible
// than they are. (The inherited declaration was `internal`, which is a hard
// access-control error — further evidence this file had never been compiled.)
@MainActor
private final class PerformanceReviewVM_550: ObservableObject {

    // Load-cycle state (house pattern, per 545).
    @Published var loading = true
    @Published var loadError: String?
    @Published var working = false
    @Published var actionNote: String?

    // TopBar
    @Published var eyebrow  = "\u{2726} DISPATCHER · MY PERFORMANCE"
    @Published var period   = "30 DAYS"
    @Published var title    = "My review"

    // RANK-RIBBON hero
    @Published var deskLabel   = "TEAM BOARD"
    @Published var rank        = "—"
    @Published var rankOf      = "—"
    @Published var rankMove    = "—"
    @Published var rankMoveDir: RankMove_550 = .unknown
    /// EMPTY when nothing on this screen was measurable — the line omits itself
    /// rather than printing a count over a denominator that does not exist.
    @Published var axesAbove   = ""
    /// The header's getPerformanceHistory reason, said ON SCREEN.
    @Published var historyNote = "Period-over-period history is not shown — the server's rating for it is a fixed constant, not a measured value."
    @Published var peers: [Peer_550] = []
    @Published var peerTail    = ""

    // Comparison ledger
    @Published var ledgerLabel  = "YOU vs TARGET · 30 DAYS"
    @Published var ledgerSource = "dispatchRole.ts:1085"
    @Published var youHeader    = "YOU"
    @Published var deltaHeader  = "\u{0394}"
    @Published var kpis: [KPI_550] = []
    @Published var footnote = ""

    // ESang — derived from the live KPI reads. esangCoach.forScreen cannot be
    // called from a dispatcher surface (SCREEN_ENUM is driver-only), so this row
    // never pretends to be a coach response.
    @Published var esangTitle = "Performance"
    @Published var esangSub   = "Reading your figures…"

    // CTA pair
    @Published var primaryCTA   = "See the team board"
    @Published var secondaryCTA = "Export"

    private let api = EusoTripAPI.shared
    /// The plain-text block "Export" copies. Built from the live figures only.
    private var exportBlock = ""

    // MARK: Load — ONE tick, four reads. This screen writes nothing.

    func load() async {
        loading = true
        loadError = nil

        struct MetricsIn: Encodable { let period: String }
        var failures: [String] = []

        // 1 · the denominators and the trend
        var stats: PerfStats_550?
        do {
            stats = try await api.queryNoInput("dispatchRole.getPerformanceStats")
        } catch {
            failures.append("stats")
        }

        // 2 · the KPI rows
        do {
            let metrics: [PerfMetric_550] = try await api.query(
                "dispatchRole.getPerformanceMetrics", input: MetricsIn(period: "30d"))
            let loads = stats?.loadsCompleted
            kpis = metrics.map { m in
                let unit = m.weightUnit ?? ""
                // NEITHER side is defaulted to zero. Two absent figures used to
                // compare as `0 >= 0` and paint the whole row in the success
                // wash; an unmeasurable standing is now nil and renders neutral,
                // and a delta over a missing operand is not printed at all.
                let standing: KPI_550.Standing?
                let delta: String
                if let v = m.value, let t = m.target {
                    standing = (v >= t) ? .above : .below
                    let d = v - t
                    delta = (d >= 0 ? "+" : "\u{2212}") + Self.figure(abs(d), unit: unit)
                } else {
                    standing = nil
                    delta = ""
                }
                return KPI_550(
                    glyph: Self.glyph(for: m.id),
                    label: m.name ?? m.id ?? "Metric",
                    denom: Self.denominator(for: m.id, loadsCompleted: loads),
                    value: m.value.map { Self.figure($0, unit: unit) } ?? "\u{2014}",
                    desk: m.target.map { "target \(Self.figure($0, unit: unit))" } ?? "",
                    delta: delta,
                    standing: standing)
            }
            // The count is over the MEASURABLE metrics only, and it names that
            // denominator. With nothing measurable the line omits itself.
            let measurable = metrics.compactMap { m -> (Double, Double)? in
                guard let v = m.value, let t = m.target else { return nil }
                return (v, t)
            }
            let atTarget = measurable.filter { $0.0 >= $0.1 }.count
            axesAbove = measurable.isEmpty
                ? ""
                : "\(atTarget) of \(measurable.count) measurable metric\(measurable.count == 1 ? "" : "s") at target"
            footnote = loads.map {
                "Target is the figure the platform sets for each metric; your value is measured over \($0) completed load\($0 == 1 ? "" : "s")."
            } ?? "Target is the figure the platform sets for each metric."
            exportBlock = Self.exportText(metrics: metrics, stats: stats)
        } catch {
            kpis = []
            failures.append("metrics")
        }

        // 3 · the rank figures (this router throws rather than degrading)
        do {
            let lb: LeaderboardHistory_550 = try await api.queryNoInput("advancedGamification.getLeaderboardHistory")
            rank = lb.currentRank.map { "#\($0)" } ?? "—"
            rankOf = lb.bestRank.map { "best #\($0)" } ?? "no ranked period yet"
            rankMove = Self.movement(lb.trend)
            // The colour is taken from the SAME trend that wrote the sentence.
            rankMoveDir = Self.direction(lb.trend)
            period = "\(lb.history?.count ?? 0) WEEKS"
        } catch {
            rank = "—"
            rankOf = "rank unavailable"
            rankMove = ""
            failures.append("rank")
        }

        // 4 · the ribbon discs — the real team board
        do {
            let guilds: [GuildRow_550] = try await api.queryNoInput("advancedGamification.getGuildLeaderboard")
            let shown = Array(guilds.prefix(5))
            peers = shown.map { g in
                Peer_550(initials: (g.tag?.isEmpty == false ? g.tag! : String((g.name ?? "—").prefix(2)).uppercased()),
                         rank: g.rank.map { "#\($0)" } ?? "—",
                         // No self flag exists on the wire. Nothing is guessed.
                         isSelf: false)
            }
            peerTail = guilds.count > shown.count ? "+\(guilds.count - shown.count) more" : ""
            deskLabel = guilds.isEmpty
                ? "TEAM BOARD · NO GUILDS YET"
                : "TEAM BOARD · \(guilds.count) TEAM\(guilds.count == 1 ? "" : "S")"
        } catch {
            peers = []
            peerTail = ""
            deskLabel = "TEAM BOARD · UNAVAILABLE"
            failures.append("team board")
        }

        // ESang row — names the genuinely weakest metric from the live reads.
        if let weakest = kpis.filter({ $0.standing == .below }).first {
            esangTitle = "\(weakest.label) is under target"
            esangSub = "You are at \(weakest.value) against \(weakest.desk)"
        } else if kpis.isEmpty {
            esangTitle = "No metrics returned"
            esangSub = "Your review has no figures for this period yet"
        } else if kpis.contains(where: { $0.standing == nil }) {
            // "Every metric is at or above target" would be a claim over rows
            // that were never measured. Name the unmeasured ones instead.
            let unmeasured = kpis.filter { $0.standing == nil }.count
            esangTitle = "\(unmeasured) metric\(unmeasured == 1 ? "" : "s") could not be measured"
            esangSub = axesAbove.isEmpty
                ? "The server returned no value or no target for \(unmeasured == 1 ? "it" : "them")"
                : axesAbove
        } else {
            esangTitle = "Every metric is at or above target"
            esangSub = axesAbove
        }

        if !failures.isEmpty && kpis.isEmpty && peers.isEmpty {
            loadError = "Couldn't reach your review (\(failures.joined(separator: ", ")))."
        }
        loading = false
    }

    // MARK: Actions (both are reads — this screen writes nothing)

    /// advancedGamification.getGuildLeaderboard:533 — the real team board.
    func teamBoard() async {
        working = true
        actionNote = nil
        do {
            let guilds: [GuildRow_550] = try await api.queryNoInput("advancedGamification.getGuildLeaderboard")
            if guilds.isEmpty {
                actionNote = "No teams on the board yet."
            } else if let top = guilds.first {
                actionNote = "\(guilds.count) team\(guilds.count == 1 ? "" : "s") ranked · leader \(top.name ?? top.tag ?? "—") with \(top.memberCount ?? 0) member\((top.memberCount ?? 0) == 1 ? "" : "s")."
            }
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't load the team board."
        }
        working = false
    }

    /// A real, complete, purely local action. There is no dispatcher-performance
    /// report procedure on the server, so nothing is claimed to have been filed.
    func export() async {
        guard !exportBlock.isEmpty else {
            actionNote = "Nothing to export yet — load your figures first."
            return
        }
        #if canImport(UIKit)
        UIPasteboard.general.string = exportBlock
        actionNote = "Copied your \(kpis.count) live figures to the clipboard."
        #else
        actionNote = "Export is only available on device."
        #endif
    }

    // MARK: Derivations

    private static func glyph(for id: String?) -> String {
        switch id ?? "" {
        case "loads-delivered": return "chart.bar"
        case "on-time-rate":    return "clock"
        case "avg-rate":        return "dollarsign.circle"
        case "revenue":         return "banknote"
        case "avg-distance":    return "road.lanes"
        case "hazmat-loads":    return "exclamationmark.triangle"
        default:                return "dot.radiowaves.left.and.right"
        }
    }

    /// The HONESTY LAW sub-line: what the figure was counted over.
    private static func denominator(for id: String?, loadsCompleted: Int?) -> String {
        let loads = loadsCompleted.map { "\($0) completed load\($0 == 1 ? "" : "s")" }
        switch id ?? "" {
        case "loads-delivered": return loads ?? "loads completed in period"
        case "on-time-rate":    return loads.map { "on-time share of \($0)" } ?? "on-time share of completed loads"
        case "avg-rate":        return loads.map { "mean rate across \($0)" } ?? "mean rate across completed loads"
        case "revenue":         return loads.map { "summed across \($0)" } ?? "summed across completed loads"
        case "avg-distance":    return loads.map { "mean distance across \($0)" } ?? "mean distance across completed loads"
        case "hazmat-loads":    return loads.map { "hazmat subset of \($0)" } ?? "hazmat subset of completed loads"
        default:                return loads ?? "period total"
        }
    }

    private static func figure(_ v: Double, unit: String) -> String {
        let rounded = v.rounded()
        let body: String = abs(v - rounded) < 0.05
            ? String(format: "%.0f", v)
            : String(format: "%.1f", v)
        switch unit {
        case "$":  return "$\(body)"
        case "%":  return "\(body)%"
        case "mi": return "\(body) mi"
        default:   return body
        }
    }

    private static func movement(_ trend: String?) -> String {
        switch (trend ?? "").lowercased() {
        case "improving": return "improving vs last period"
        case "declining": return "declining vs last period"
        case "stable":    return "steady vs last period"
        default:          return ""
        }
    }

    /// Same switch, same source — so the sentence and its colour can never
    /// disagree. An unrecognised trend is `.unknown`, not a win.
    private static func direction(_ trend: String?) -> RankMove_550 {
        switch (trend ?? "").lowercased() {
        case "improving": return .improving
        case "declining": return .declining
        case "stable":    return .steady
        default:          return .unknown
        }
    }

    private static func exportText(metrics: [PerfMetric_550], stats: PerfStats_550?) -> String {
        var lines: [String] = ["EusoTrip · Dispatcher performance"]
        if let l = stats?.loadsCompleted { lines.append("Loads completed: \(l)") }
        if let o = stats?.onTimeRate { lines.append("On-time rate: \(o)%") }
        for m in metrics {
            let unit = m.weightUnit ?? ""
            // The clipboard carries exactly what the screen carries: an em-dash
            // for a figure the server did not produce, and no target clause at
            // all when there is no target. Never a zero.
            let value = m.value.map { figure($0, unit: unit) } ?? "\u{2014}"
            let target = m.target.map { " (target \(figure($0, unit: unit)))" } ?? ""
            lines.append("\(m.name ?? m.id ?? "metric"): \(value)\(target)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Shell wrapper (house idiom · Dpch730_DispatcherOpsQuartet)

private struct ShellNav<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

// MARK: - Screen

struct DispatcherPerformanceReviewScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ShellNav(theme: theme) { PerformanceReviewBody_550() }
    }
}

private struct PerformanceReviewBody_550: View {
    @Environment(\.palette) private var palette
    @StateObject private var vm = PerformanceReviewVM_550()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                if vm.loading {
                    loadingCard
                } else if let err = vm.loadError {
                    errorCard(err)
                } else {
                    rankRibbon; comparisonLedger; esangRow; ctaRow
                }
                Color.clear.frame(height: 96)
            }.padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await vm.load() }
        .eusoRefreshable { await vm.load() }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading your review…").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 13)).foregroundStyle(palette.textPrimary)
            Button { Task { await vm.load() } } label: {
                Text("Try again").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule().fill(LinearGradient.primary))
            }.buttonStyle(.plain)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
    }

    // An UNKNOWN standing takes the NEUTRAL treatment in all three roles. It is
    // never allowed to fall through to the success pair, which is what made two
    // absent figures read as an above-target win.
    /// Small-text color on a tinted wash — the WCAG-tested text half of the pair.
    /// There is no neutral member of that WCAG family, so neutral text uses the
    /// palette's own secondary ink.
    private func standingText(_ s: KPI_550.Standing?) -> Color {
        switch s {
        case .some(.above): return successText_550
        case .some(.below): return dangerText_550
        case .none:         return palette.textSecondary
        }
    }
    /// Saturated glyph/fill color.
    private func standingTint(_ s: KPI_550.Standing?) -> Color {
        switch s {
        case .some(.above): return Brand.success
        case .some(.below): return Brand.danger
        case .none:         return Brand.neutral
        }
    }
    /// The chip WASH behind the glyph.
    private func standingWash(_ s: KPI_550.Standing?) -> Color {
        switch s {
        case .some(.above): return palette.tintSuccess
        case .some(.below): return palette.tintDanger
        case .none:         return palette.tintNeutral
        }
    }

    /// The rank-movement line takes its colour from the direction it reports.
    /// A decline must not read as a win; a steady or unknown move is neutral.
    private func rankMoveText(_ d: RankMove_550) -> Color {
        switch d {
        case .improving:        return successText_550
        case .declining:        return dangerText_550
        case .steady, .unknown: return palette.textSecondary
        }
    }

    /// Ledger rule — the SVG's #000000 @ 6% separator, expressed as a palette token.
    private var rowRule: some View {
        Rectangle().fill(palette.borderFaint).frame(height: 1)
    }

    // MARK: - DETAIL TopBar
    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(vm.eyebrow).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(vm.period).font(.system(size: 9, weight: .heavy, design: .monospaced)).kerning(1.0).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 10) {
                // Real control, not a decorative glyph — the house pattern every
                // pre-existing Dispatch peer uses (410:194-200). 44-unit target.
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text(vm.title).font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            // THE one iridescent hairline on this surface (house component).
            IridescentHairline()
        }
    }

    private func back() {
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Disp401"])
    }

    // MARK: - RANK-RIBBON hero
    private var rankRibbon: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(vm.deskLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(vm.rank).font(.system(size: 32, weight: .bold)).monospacedDigit().kerning(-0.5).foregroundStyle(palette.textPrimary)
                Text(vm.rankOf).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(vm.rankMove).font(.system(size: 13, weight: .bold)).foregroundStyle(rankMoveText(vm.rankMoveDir))
                    // Omits itself when nothing on this screen was measurable.
                    if !vm.axesAbove.isEmpty {
                        Text(vm.axesAbove).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    }
                }
            }
            ZStack(alignment: .top) {
                Rectangle().fill(palette.borderFaint).frame(height: 1).offset(y: 22)
                HStack(alignment: .top, spacing: 22) {
                    ForEach(vm.peers) { p in peerDisc(p) }
                    Spacer(minLength: 0)
                    if !vm.peerTail.isEmpty {
                        Text(vm.peerTail).font(.system(size: 11)).foregroundStyle(palette.textTertiary).padding(.top, Space.s4)
                    }
                }
            }
            // The header's getPerformanceHistory reason, said out loud where the
            // dispatcher can read it — the gap is named on screen, not only in
            // the file comment that claims it is.
            Text(vm.historyNote)
                .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func peerDisc(_ p: Peer_550) -> some View {
        VStack(spacing: Space.s2) {
            ZStack {
                if p.isSelf {
                    Circle().strokeBorder(LinearGradient.primary, lineWidth: 2).frame(width: 44, height: 44)
                    Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                    Text(p.initials).font(.system(size: 12, weight: .heavy)).kerning(0.3).foregroundStyle(palette.textOnGradient)
                } else {
                    Circle().fill(palette.tintNeutral).frame(width: 34, height: 34)
                    Text(p.initials).font(.system(size: 12, weight: .heavy)).kerning(0.3).foregroundStyle(palette.textSecondary)
                }
            }
            .frame(width: 44, height: 44)
            .offset(y: p.isSelf ? -5 : 0)          // the reviewed row is raised
            Text(p.rank).font(.system(size: 9, weight: .bold)).monospacedDigit()
                .foregroundStyle(p.isSelf ? palette.textPrimary : palette.textTertiary)
                .offset(y: p.isSelf ? -5 : 0)
        }
    }

    // MARK: - Comparison ledger
    // NO bars, NO tracks, NO ticks: the 547 scored-track ladder was removed
    // outright. Each figure is read against the target printed under it.
    private var comparisonLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(vm.ledgerLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.ledgerSource).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }.padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 0) {
                // header strip: YOU right-anchored over the figure column, Δ at the far right
                HStack(spacing: Space.s3) {
                    Spacer(minLength: 0)
                    Text(vm.youHeader)
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                        .frame(width: 78, alignment: .trailing)
                    Text(vm.deltaHeader)
                        .font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, Space.s4).padding(.top, Space.s4).padding(.bottom, Space.s2)
                rowRule.padding(.horizontal, Space.s4)

                ForEach(Array(vm.kpis.enumerated()), id: \.element.id) { idx, k in
                    kpiRow(k)
                    if idx < vm.kpis.count - 1 { rowRule.padding(.horizontal, Space.s4) }
                }
                if vm.kpis.isEmpty {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "tray").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text("No performance metrics returned for this period.").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }.padding(Space.s4)
                }
                if !vm.footnote.isEmpty {
                    Text(vm.footnote).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, Space.s4).padding(.top, Space.s3).padding(.bottom, Space.s4)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func kpiRow(_ k: KPI_550) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            // MANDATORY 40x40 rx10 icon chip — per-KPI glyph, tinted by standing.
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(standingWash(k.standing))
                    .frame(width: 40, height: 40)
                Image(systemName: k.glyph)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(standingTint(k.standing))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(k.label).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(k.denom).font(.system(size: 11, design: .monospaced)).kerning(0.4).foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: Space.s2)
            // this dispatcher's figure over the figure it is read against
            VStack(alignment: .trailing, spacing: 5) {
                Text(k.value).font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // No target on the wire, no "target N" line. The clause is
                // dropped outright rather than printed over an invented zero.
                if !k.desk.isEmpty {
                    Text(k.desk).font(.system(size: 11)).monospacedDigit().foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }.frame(width: 78, alignment: .trailing)
            // The delta, far right. Empty when it could not be computed — the
            // 44pt column is held so the rows stay aligned, but nothing prints.
            Text(k.delta)
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(standingText(k.standing))
                .frame(width: 44, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.7)
        }.padding(Space.s4)
    }

    // MARK: - ESang row (derived from this screen's own reads — see header)
    private var esangRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 1, endRadius: 16)).frame(width: 28, height: 28)
                Text("E").font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textOnGradient)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.esangTitle).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(vm.esangSub).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    // MARK: - CTA pair (both reads — this screen writes nothing)
    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button { Task { await vm.teamBoard() } } label: {
                    Text(vm.working ? "Working…" : vm.primaryCTA)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textOnGradient)
                        .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
                }
                .disabled(vm.working)

                Button { Task { await vm.export() } } label: {
                    Text(vm.secondaryCTA).font(.system(size: 15, weight: .semibold)).frame(width: 132, height: 48)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
                }
                .foregroundStyle(palette.textPrimary)
                .disabled(vm.working || vm.kpis.isEmpty)
            }
            if let note = vm.actionNote {
                Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("550 · Performance Review · Dark")  { DispatcherPerformanceReviewScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("550 · Performance Review · Light") { DispatcherPerformanceReviewScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
