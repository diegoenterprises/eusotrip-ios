//
//  Dpch770_DispatcherSettlementDetailOctet.swift
//  EusoTrip — Dispatcher · Settlement-detail octet (500-507).
//
//  Pixel-match to:
//    500 Dispatcher Settlement Review
//    501 Dispatcher Settlement DSO Detail
//    502 Dispatcher Settlement Quick-Pay Velocity Detail
//    503 Dispatcher Settlement Open Ledger Balance Detail
//    504 Dispatcher Settlement Adjustment-Ratio (Clean Rate) Detail
//    505 Dispatcher Settlement Onboarding Step Detail
//    506 Dispatcher Settlement Compliance Row Detail
//    507 Dispatcher Settlement Quarter Trajectory Detail
//
//  All 8 share `DispatcherSettlementBody`. Body reads
//  `payroll.getSettlementStats` for live finance metrics. Bottom nav
//  frozen (Dispatcher: Home / Board / ESANG / Me).
//
//  ZERO-FABRICATION binding (2026-06-06):
//  Bound to `payroll.getSettlementStats` (frontend/server/routers/payroll.ts
//  §getSettlementStats). The proc returns ONLY three live fields, computed
//  from completed payrollItems for the resolved company:
//      • totalSettled / totalPaid  = SUM(netAmount) of completed items
//      • total                     = COUNT of completed items
//  The proc hard-codes `pending`, `thisWeek`, and `totalRevenue` to 0 — they
//  carry no signal, so nothing is derived from them. There is NO live source
//  for: company/carrier identity name, GRADE, DSO, QPAY velocity, open-ledger
//  balance, clean/adjustment rate, onboarding steps, compliance rows, per-class
//  breakdowns, §-citations, or per-quarter rollups. Every one of those renders
//  an honest em-dash ("—"). Identity comes from the authenticated session
//  (`session.user`), never a hardcoded persona.
//

import SwiftUI

private let kEmDash = "—"

/// Wire shape of `payroll.getSettlementStats`. Mirrors the proc's return object
/// 1:1. `pending`, `thisWeek`, and `totalRevenue` are hard-zeroed server-side and
/// are NOT surfaced as metrics.
private struct DSPayrollStats: Decodable, Hashable {
    let totalPaid: Double?
    let pending: Double?
    let thisWeek: Double?
    let total: Int?
    let totalRevenue: Double?
    let totalSettled: Double?
}

enum DispatcherSettlementKind: String {
    case review, dso, qpayVelocity, openLedger, cleanRate, onboarding, compliance, quarter
}

private struct DSConfig {
    let eyebrow: String
    let title: String
    let subhead: String
    let pillCopy: String
}

private extension DispatcherSettlementKind {
    var config: DSConfig {
        switch self {
        case .review:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · REVIEW",
                         title: "Settlement review",
                         subhead: "SETTLEMENT STREAMS",
                         pillCopy: "Review settled volume and cleared-event count from completed payroll runs.")
        case .dso:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · DSO",
                         title: "DSO axis",
                         subhead: "SCORE-COMPOSITE",
                         pillCopy: "Days-sales-outstanding grading is not yet computed by the settlement service.")
        case .qpayVelocity:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · QPAY VELOCITY",
                         title: "QPAY velocity",
                         subhead: "SCORE-COMPOSITE",
                         pillCopy: "Quick-pay velocity grading is not yet computed by the settlement service.")
        case .openLedger:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · OPEN LEDGER",
                         title: "Open ledger",
                         subhead: "SCORE-COMPOSITE",
                         pillCopy: "Open-balance ledger totals are not yet reported by the settlement service.")
        case .cleanRate:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · CLEAN RATE",
                         title: "Clean rate",
                         subhead: "SCORE-COMPOSITE",
                         pillCopy: "Adjustment / clean-rate ratios are not yet computed by the settlement service.")
        case .onboarding:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · ONBOARDING",
                         title: "Onboarding",
                         subhead: "SCORE-COMPOSITE",
                         pillCopy: "Per-class onboarding step scoring is not yet reported by the settlement service.")
        case .compliance:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · COMPLIANCE",
                         title: "Compliance",
                         subhead: "SCORE-COMPOSITE",
                         pillCopy: "Per-class compliance-row scoring is not yet reported by the settlement service.")
        case .quarter:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · TRAJECTORY",
                         title: "Quarter trajectory",
                         subhead: "SCORE-COMPOSITE",
                         pillCopy: "Per-quarter trajectory rollups are not yet reported by the settlement service.")
        }
    }
}

private struct DispatcherSettlementShell<Content: View>: View {
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

private struct DispatcherSettlementBody: View {
    let kind: DispatcherSettlementKind

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var stats: DSPayrollStats?

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
        .eusoRefreshable { await load() }
    }

    private func header(_ c: DSConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: DSConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(statusPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    /// Status pill. Only the `review` lane has a live composite to show
    /// (settled volume + cleared-event count). Every other lane has no live
    /// grade/score source, so it renders an honest em-dash.
    private var statusPill: String {
        switch kind {
        case .review:
            let settled = currencyKLive(stats?.totalSettled)
            let events = stats?.total.map(String.init) ?? kEmDash
            return "SETTLED \(settled) · \(events) EVENTS"
        default:
            return kEmDash
        }
    }

    private var identityRow: some View {
        // Identity from the authenticated session — never a hardcoded persona.
        let displayName = session.user?.name ?? "Dispatch user"
        let companyLine = session.user?.companyId.map { "companyId · \($0)" } ?? kEmDash
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "dollarsign.circle.fill").font(.system(size: 14)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(displayName) · Settlement Streams").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(companyLine).font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let s = stats
        // The only live values from payroll.getSettlementStats are settled
        // volume (totalSettled / totalPaid) and cleared-event count (total).
        let settled = currencyKLive(s?.totalSettled)
        let volume = currencyKLive(s?.totalPaid)
        let events = s?.total.map(String.init) ?? kEmDash
        // Lane-specific grades/scores have no live source → honest em-dash.
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",     kEmDash,  "no grading source",   .gray),
                    ("DSO",       kEmDash,  "no DSO source",       .gray),
                    ("SETTLED",   settled,  "completed runs",      .blue),
                    ("EVENTS",    events,   "cleared",             .blue),
                ]
            case .dso:
                return [
                    ("DSO",       kEmDash,  "no DSO source",       .gray),
                    ("FLOOR",     kEmDash,  "no floor source",    .gray),
                    ("EVENTS",    events,   "cleared",             .blue),
                    ("GRADE",     kEmDash,  "no grading source",  .gray),
                ]
            case .qpayVelocity:
                return [
                    ("QPAY",      kEmDash,  "no velocity source",  .gray),
                    ("CEILING",   kEmDash,  "no ceiling source",  .gray),
                    ("VOLUME",    volume,   "settled, completed",  .blue),
                    ("GRADE",     kEmDash,  "no grading source",  .gray),
                ]
            case .openLedger:
                return [
                    ("OPEN",      kEmDash,  "no ledger source",    .gray),
                    ("FLOOR",     kEmDash,  "no floor source",    .gray),
                    ("EVENTS",    events,   "cleared",             .blue),
                    ("GRADE",     kEmDash,  "no grading source",  .gray),
                ]
            case .cleanRate:
                return [
                    ("CLEAN",     kEmDash,  "no rate source",      .gray),
                    ("CEILING",   kEmDash,  "no ceiling source",  .gray),
                    ("ADJUST",    kEmDash,  "no adjust source",   .gray),
                    ("GRADE",     kEmDash,  "no grading source",  .gray),
                ]
            case .onboarding:
                return [
                    ("STEPS",     kEmDash,  "no steps source",     .gray),
                    ("CEILING",   kEmDash,  "no ceiling source",  .gray),
                    ("OPEN-IP",   kEmDash,  "no progress source", .gray),
                    ("GRADE",     kEmDash,  "no grading source",  .gray),
                ]
            case .compliance:
                return [
                    ("ROWS",      kEmDash,  "no rows source",      .gray),
                    ("CEILING",   kEmDash,  "no ceiling source",  .gray),
                    ("AUDIT",     kEmDash,  "no audit source",    .gray),
                    ("GRADE",     kEmDash,  "no grading source",  .gray),
                ]
            case .quarter:
                return [
                    ("YEAR-AVG",  kEmDash,  "no rollup source",    .gray),
                    ("CEILING",   kEmDash,  "no ceiling source",  .gray),
                    ("EVENTS",    events,   "cleared",             .blue),
                    ("GRADE",     kEmDash,  "no grading source",  .gray),
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
        // Only the review lane has a live figure to act on. Every score-driven
        // lane has no live source, so the next-step copy says so honestly.
        let copy: String = {
            switch kind {
            case .review:
                let events = stats?.total.map(String.init) ?? kEmDash
                let settled = currencyKLive(stats?.totalSettled)
                return "\(events) cleared settlement events totalling \(settled). Refresh to reconcile against the latest completed payroll run."
            default:
                return "No live score is reported by the settlement service for this lane yet. Values render as \(kEmDash) until the metric is wired."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("payroll.getSettlementStats") } catch { /* */ }
    }
}

/// Currency formatter for a genuinely-optional live figure. Returns an honest
/// em-dash when the field is absent — never a fabricated fallback amount.
private func currencyKLive(_ value: Double?) -> String {
    guard let v = value else { return kEmDash }
    if v >= 1000 { return String(format: "$%.1fK", v / 1000) }
    return String(format: "$%.0f", v)
}

// MARK: - Screens (500-507)

struct DispatcherSettlementReviewScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherSettlementShell(theme: theme) { DispatcherSettlementBody(kind: .review) } }
}
struct DispatcherSettlementDSOScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherSettlementShell(theme: theme) { DispatcherSettlementBody(kind: .dso) } }
}
struct DispatcherSettlementQPAYScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherSettlementShell(theme: theme) { DispatcherSettlementBody(kind: .qpayVelocity) } }
}
struct DispatcherSettlementOpenLedgerScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherSettlementShell(theme: theme) { DispatcherSettlementBody(kind: .openLedger) } }
}
struct DispatcherSettlementCleanRateScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherSettlementShell(theme: theme) { DispatcherSettlementBody(kind: .cleanRate) } }
}
struct DispatcherSettlementOnboardingScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherSettlementShell(theme: theme) { DispatcherSettlementBody(kind: .onboarding) } }
}
struct DispatcherSettlementComplianceScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherSettlementShell(theme: theme) { DispatcherSettlementBody(kind: .compliance) } }
}
struct DispatcherSettlementQuarterScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherSettlementShell(theme: theme) { DispatcherSettlementBody(kind: .quarter) } }
}

// MARK: - Previews

#Preview("500 Review · Dark")       { DispatcherSettlementReviewScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("501 DSO · Light")         { DispatcherSettlementDSOScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("502 QPAY · Dark")         { DispatcherSettlementQPAYScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("503 Open · Light")        { DispatcherSettlementOpenLedgerScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("504 Clean · Dark")        { DispatcherSettlementCleanRateScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("505 Onboarding · Light")  { DispatcherSettlementOnboardingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("506 Compliance · Dark")   { DispatcherSettlementComplianceScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("507 Quarter · Light")     { DispatcherSettlementQuarterScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
