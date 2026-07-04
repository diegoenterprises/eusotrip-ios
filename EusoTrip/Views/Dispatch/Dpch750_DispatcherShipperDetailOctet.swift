//
//  Dpch750_DispatcherShipperDetailOctet.swift
//  EusoTrip — Dispatcher · Shipper-detail octet (440-447).
//
//  Pixel-match to:
//    440 Dispatcher Shipper Review
//    441 Dispatcher Shipper Pull-Volume Detail
//    442 Dispatcher Shipper Tender-Win Detail
//    443 Dispatcher Shipper Payment-Behavior Detail
//    444 Dispatcher Shipper Lane-Win Detail
//    445 Dispatcher Shipper Account-Health Detail
//    446 Dispatcher Shipper Onboarding Step Detail
//    447 Dispatcher Shipper Quarter Detail
//
//  All 8 screens share `DispatcherShipperDetailBody`, parameterized
//  by `ShipperDetailKind`. Body reads two live procs and NOTHING ELSE:
//
//    • shipperScorecard.getScorecard  → grade / overallScore / metrics
//      { tenderAcceptance, completionRate, cancellationRate, averageRate,
//        volumeConsistency, totalLoads, deliveredCount, cancelledCount } +
//      volumeByMonth (month→count map). These are the ONLY KPI sources.
//    • users.getById                  → the viewed shipper's real identity
//      (user.name / user.email / company.name). NEVER a hardcoded persona.
//
//  ZERO fabrication: every metric below maps to a field the server proc
//  actually returns. Fields the proc does NOT expose (DSO / payment cadence,
//  per-lane mix, per-quarter rollups, onboarding-step ladder, multi-account
//  roster, prior-period deltas) render an honest "—" — never an invented
//  literal. Bottom nav frozen. Visual chrome/sections preserved verbatim.
//

import SwiftUI

// MARK: - Live response shapes

/// Mirrors `shipperScorecard.getScorecard` (frontend/server/routers/
/// shipperScorecard.ts) verbatim — including `volumeByMonth`, the only
/// time-series the proc returns.
private struct ShipperScorecardResp: Decodable, Hashable {
    let shipperId: Int?
    let periodDays: Int?
    let overallScore: Int?
    let grade: String?
    let metrics: Metrics?
    let volumeByMonth: [String: Int]?
    struct Metrics: Decodable, Hashable {
        let tenderAcceptance: Double?    // %  (total - cancelled) / total
        let completionRate: Double?      // %  delivered / total
        let cancellationRate: Double?    // %  cancelled / total
        let averageRate: Double?         // USD avg rate of delivered loads — NOT days
        let volumeConsistency: Double?   // 0–100
        let totalLoads: Int?
        let deliveredCount: Int?
        let cancelledCount: Int?
    }
}

/// Mirrors `users.getById` (frontend/server/routers/users.ts) — only the
/// identity fields this screen renders. The viewed shipper's name + company
/// come from here, never from a literal persona or the signed-in session.
/// users.getById returns a FLAT object (no nested user/company). It carries the
/// contact `name`/`email` and the `companyName`; it does NOT return DOT/MC.
private struct ShipperIdentityResp: Decodable, Hashable {
    let id: String?
    let name: String?
    let email: String?
    let companyId: Int?
    let companyName: String?
}

// MARK: - Kind + config

enum ShipperDetailKind: String {
    case review, pullVolume, tenderWin, paymentBehavior, laneWin, accountHealth, onboarding, quarter
}

private struct ShipperDetailConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let statusPill: String
}

private extension ShipperDetailKind {
    var config: ShipperDetailConfig {
        switch self {
        case .review:
            return .init(eyebrow: "DISPATCHER · SHIPPER · REVIEW",
                         citation: "DISPATCHER REVIEW · SHIPPER SCORECARD",
                         title: "Shipper review",
                         subhead: "Composite scorecard · 90-day window",
                         pillCopy: "Composite grade across tender acceptance, completion, cancellation and volume consistency.",
                         statusPill: "SCORECARD · 90D")
        case .pullVolume:
            return .init(eyebrow: "DISPATCHER · SHIPPER · PULL-VOLUME",
                         citation: "DISPATCHER PULL VOLUME · 90D",
                         title: "Pull volume",
                         subhead: "Monthly load volume · 90-day window",
                         pillCopy: "Load volume by month for this shipper over the scorecard window.",
                         statusPill: "VOLUME · 90D")
        case .tenderWin:
            return .init(eyebrow: "DISPATCHER · SHIPPER · TENDER-WIN",
                         citation: "DISPATCHER TENDER · 90D",
                         title: "Tender win",
                         subhead: "Tender acceptance · 90-day window",
                         pillCopy: "Accepted vs cancelled loads against total tendered over the window.",
                         statusPill: "TENDER · 90D")
        case .paymentBehavior:
            return .init(eyebrow: "DISPATCHER · SHIPPER · PAYMENT-BEHAVIOR",
                         citation: "DISPATCHER PAYMENT · 90D",
                         title: "Payment behavior",
                         subhead: "Settlement signals · 90-day window",
                         pillCopy: "Delivered-load volume and average load rate. Days-to-pay is not yet wired.",
                         statusPill: "PAYMENT · 90D")
        case .laneWin:
            return .init(eyebrow: "DISPATCHER · SHIPPER · LANE-WIN",
                         citation: "DISPATCHER LANE · 90D",
                         title: "Lane mix",
                         subhead: "Per-lane mix · 90-day window",
                         pillCopy: "Per-lane win mix isn't part of the scorecard data yet.",
                         statusPill: "LANE · 90D")
        case .accountHealth:
            return .init(eyebrow: "DISPATCHER · SHIPPER · ACCOUNT-HEALTH",
                         citation: "DISPATCHER ACCOUNT-HEALTH · 90D",
                         title: "Account health",
                         subhead: "Health signals · 90-day window",
                         pillCopy: "Completion, cancellation and volume-consistency signals for this account.",
                         statusPill: "HEALTH · 90D")
        case .onboarding:
            return .init(eyebrow: "DISPATCHER · SHIPPER · ONBOARDING-STEP",
                         citation: "DISPATCHER STEP-LADDER · 90D",
                         title: "Onboarding step",
                         subhead: "Step ladder · 90-day window",
                         pillCopy: "Onboarding-step ladder isn't part of the scorecard data yet.",
                         statusPill: "ONBOARDING · 90D")
        case .quarter:
            return .init(eyebrow: "DISPATCHER · SHIPPER · QUARTER",
                         citation: "DISPATCHER QUARTER · 365D",
                         title: "Quarter trajectory",
                         subhead: "Trailing-year window",
                         pillCopy: "Per-quarter rollups are not yet exposed; monthly volume over the year is shown.",
                         statusPill: "TRAJECTORY · 365D")
        }
    }
    var period: Int { self == .quarter ? 365 : 90 }
}

// MARK: - Shared shell + body

private struct DispatcherShipperDetailShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "ESANG", systemImage: "sparkles", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatcherShipperDetailBody: View {
    let shipperId: String
    let kind: ShipperDetailKind

    @Environment(\.palette) private var palette
    @State private var resp: ShipperScorecardResp?
    @State private var identity: ShipperIdentityResp?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                pill(c)
                identityRow
                kpiGrid
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ c: ShipperDetailConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: ShipperDetailConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(c.statusPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    /// Identity bound to `users.getById` for the viewed shipper. Company name
    /// is the headline; the contact name / email line falls back to "—" when
    /// the proc returns no value. Never a hardcoded persona.
    private var identityRow: some View {
        let company = identity?.companyName
        let headline = (company?.isEmpty == false ? company : identity?.name) ?? "—"
        let sub: String = {
            var parts: [String] = []
            // When the company is the headline, surface the contact name below.
            if company?.isEmpty == false, let n = identity?.name, !n.isEmpty { parts.append(n) }
            if let e = identity?.email, !e.isEmpty { parts.append(e) }
            return parts.isEmpty ? "shipper-of-record" : parts.joined(separator: " · ")
        }()
        let initials = avatarInitials(headline)
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(initials).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let m = resp?.metrics
        let grade = resp?.grade ?? "—"
        let months = resp?.volumeByMonth ?? [:]
        // The dash placeholder used everywhere a field is genuinely absent.
        let dash = "—"
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",       grade,                          composite,                       .green),
                    ("TENDER-WIN",  pct(m?.tenderAcceptance),       "accepted of tendered · 90d",    .green),
                    ("COMPLETION",  pct(m?.completionRate),         "delivered of total · 90d",      .blue),
                    ("LOADS",       intStr(m?.totalLoads),          "total · 90d window",            .blue),
                ]
            case .pullVolume:
                let monthCount = months.isEmpty ? dash : "\(months.count)"
                let peak = months.values.max()
                return [
                    ("LOADS",       intStr(m?.totalLoads),          "total · 90d window",            .blue),
                    ("MONTHS",      monthCount,                     "with recorded volume",          .blue),
                    ("PEAK / MO",   peak.map(String.init) ?? dash,  "busiest month in window",       .green),
                    ("CONSISTENCY", num(m?.volumeConsistency),      "volume consistency · 0–100",    .green),
                ]
            case .tenderWin:
                let accepted: Int? = {
                    guard let t = m?.totalLoads, let c = m?.cancelledCount else { return nil }
                    return max(0, t - c)
                }()
                return [
                    ("TENDERED",    intStr(m?.totalLoads),          "total loads · 90d",             .blue),
                    ("ACCEPTED",    intStr(accepted),               pctSuffix(m?.tenderAcceptance, "acceptance"), .green),
                    ("CANCELLED",   intStr(m?.cancelledCount),      pctSuffix(m?.cancellationRate, "cancel rate"), .red),
                    ("GRADE",       grade,                          "tender pillar",                 .green),
                ]
            case .paymentBehavior:
                return [
                    ("DELIVERED",   intStr(m?.deliveredCount),      "delivered loads · 90d",         .green),
                    ("LOADS",       intStr(m?.totalLoads),          "total · 90d window",            .blue),
                    ("AVG RATE",    usd(m?.averageRate),            "per delivered load",            .blue),
                    ("DAYS TO PAY", dash,                           "settlement cadence not wired",  .orange),
                ]
            case .laneWin:
                return [
                    ("LANES",       dash,                           "per-lane mix not wired",        .blue),
                    ("WON",         dash,                           "per-lane mix not wired",        .green),
                    ("FLAGSHIP",    dash,                           "per-lane mix not wired",        .green),
                    ("GRADE",       grade,                          "composite pillar",              .green),
                ]
            case .accountHealth:
                return [
                    ("COMPLETION",  pct(m?.completionRate),         "delivered of total · 90d",      .green),
                    ("CANCEL",      pct(m?.cancellationRate),       "cancelled of total · 90d",      .red),
                    ("CONSISTENCY", num(m?.volumeConsistency),      "volume consistency · 0–100",    .blue),
                    ("GRADE",       grade,                          "account pillar",                .green),
                ]
            case .onboarding:
                return [
                    ("STEPS",       dash,                           "step ladder not wired",         .blue),
                    ("TERMINAL",    dash,                           "step ladder not wired",         .green),
                    ("IN-PROG",     dash,                           "step ladder not wired",         .orange),
                    ("GRADE",       grade,                          "composite pillar",              .green),
                ]
            case .quarter:
                let monthCount = months.isEmpty ? dash : "\(months.count)"
                return [
                    ("QUARTERS",    dash,                           "per-quarter rollup not wired",  .blue),
                    ("MONTHS",      monthCount,                     "with volume · trailing year",   .blue),
                    ("LOADS",       intStr(m?.totalLoads),          "total · trailing year",         .blue),
                    ("GRADE",       grade,                          "year-rolling pillar",           .green),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .review:           return "Composite grade is the tender-priority and payment-terms anchor for this shipper. Refresh weekly."
            case .pullVolume:       return "Monthly volume reflects this shipper's pull cadence over the window. Watch for a falling trend."
            case .tenderWin:        return "Acceptance vs cancellation tells you how reliably this shipper's tenders convert. Investigate cancellations."
            case .paymentBehavior:  return "Delivered volume and average rate are live; days-to-pay surfaces once settlement cadence is wired."
            case .laneWin:          return "Per-lane win mix is not yet exposed by the scorecard proc — shown as “—” until the lane breakdown ships."
            case .accountHealth:    return "Completion, cancellation and volume-consistency are the live health signals for this account."
            case .onboarding:       return "The onboarding-step ladder is not yet exposed — shown as “—” until the step rollup ships."
            case .quarter:          return "Per-quarter rollups are not yet exposed; monthly volume over the trailing year is shown instead."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Honest formatters (no invented fallbacks — "—" when absent)

    private var composite: String {
        guard let s = resp?.overallScore else { return "—" }
        return "composite \(s)/100"
    }

    private func pct(_ raw: Double?) -> String {
        guard let raw else { return "—" }
        return raw.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(raw))%"
            : String(format: "%.1f%%", raw)
    }

    private func pctSuffix(_ raw: Double?, _ label: String) -> String {
        guard let raw else { return "\(label) · 90d" }
        let v = raw.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(raw))%" : String(format: "%.1f%%", raw)
        return "\(v) \(label)"
    }

    private func num(_ raw: Double?) -> String {
        guard let raw else { return "—" }
        return raw.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(raw))" : String(format: "%.1f", raw)
    }

    private func intStr(_ raw: Int?) -> String {
        guard let raw else { return "—" }
        return "\(raw)"
    }

    private func usd(_ raw: Double?) -> String {
        guard let raw else { return "—" }
        return "$\(Int(raw))"
    }

    private func avatarInitials(_ s: String) -> String {
        let words = s.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return letters.isEmpty ? "·" : letters
    }

    private func load() async {
        let sid = Int(shipperId) ?? 0
        // KPI source — shipperScorecard.getScorecard.
        struct ScoreIn: Encodable { let shipperId: Int; let periodDays: Int }
        do {
            resp = try await EusoTripAPI.shared.query(
                "shipperScorecard.getScorecard",
                input: ScoreIn(shipperId: sid, periodDays: kind.period)
            )
        } catch { /* leave nil → KPIs render "—" */ }

        // Identity source — users.getById (the viewed shipper, not the session).
        // Server input is z.string() (no coerce) → id MUST be sent as a String.
        struct UserIn: Encodable { let id: String }
        do {
            identity = try await EusoTripAPI.shared.query(
                "users.getById",
                input: UserIn(id: shipperId)
            )
        } catch { /* leave nil → identity renders "—" (e.g. cross-shipper 403) */ }
    }
}

// MARK: - Screens (440-447)

struct DispatcherShipperReviewScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { DispatcherShipperDetailShell(theme: theme) { DispatcherShipperDetailBody(shipperId: shipperId, kind: .review) } }
}
struct DispatcherShipperPullVolumeScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { DispatcherShipperDetailShell(theme: theme) { DispatcherShipperDetailBody(shipperId: shipperId, kind: .pullVolume) } }
}
struct DispatcherShipperTenderWinScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { DispatcherShipperDetailShell(theme: theme) { DispatcherShipperDetailBody(shipperId: shipperId, kind: .tenderWin) } }
}
struct DispatcherShipperPaymentBehaviorScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { DispatcherShipperDetailShell(theme: theme) { DispatcherShipperDetailBody(shipperId: shipperId, kind: .paymentBehavior) } }
}
struct DispatcherShipperLaneWinScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { DispatcherShipperDetailShell(theme: theme) { DispatcherShipperDetailBody(shipperId: shipperId, kind: .laneWin) } }
}
struct DispatcherShipperAccountHealthScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { DispatcherShipperDetailShell(theme: theme) { DispatcherShipperDetailBody(shipperId: shipperId, kind: .accountHealth) } }
}
struct DispatcherShipperOnboardingStepScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { DispatcherShipperDetailShell(theme: theme) { DispatcherShipperDetailBody(shipperId: shipperId, kind: .onboarding) } }
}
struct DispatcherShipperQuarterScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { DispatcherShipperDetailShell(theme: theme) { DispatcherShipperDetailBody(shipperId: shipperId, kind: .quarter) } }
}

// MARK: - Previews

#Preview("440 Review · Dark")       { DispatcherShipperReviewScreen(theme: Theme.dark, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("441 Pull · Light")        { DispatcherShipperPullVolumeScreen(theme: Theme.light, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("442 Tender · Dark")       { DispatcherShipperTenderWinScreen(theme: Theme.dark, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("443 Payment · Light")     { DispatcherShipperPaymentBehaviorScreen(theme: Theme.light, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("444 Lane · Dark")         { DispatcherShipperLaneWinScreen(theme: Theme.dark, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("445 Account · Light")     { DispatcherShipperAccountHealthScreen(theme: Theme.light, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("446 Onboarding · Dark")   { DispatcherShipperOnboardingStepScreen(theme: Theme.dark, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("447 Quarter · Light")     { DispatcherShipperQuarterScreen(theme: Theme.light, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
