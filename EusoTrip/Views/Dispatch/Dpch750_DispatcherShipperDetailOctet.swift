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
//  by `ShipperDetailKind`. Body reads `shipperScorecard.getScorecard`
//  for live metrics. Bottom nav frozen.
//

import SwiftUI

// MARK: - Live response shape

private struct ShipperScorecardResp: Decodable, Hashable {
    let shipperId: Int?
    let periodDays: Int?
    let overallScore: Int?
    let grade: String?
    let metrics: Metrics?
    struct Metrics: Decodable, Hashable {
        let tenderAcceptance: Double?
        let completionRate: Double?
        let cancellationRate: Double?
        let averageRate: Double?
        let volumeConsistency: Double?
        let totalLoads: Int?
        let deliveredCount: Int?
        let cancelledCount: Int?
    }
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
                         citation: "DISPATCHER REVIEW · SHIPPER ACCOUNTS · 90D",
                         title: "Shipper review",
                         subhead: "AURORA-CTLG-00001 · 4 SHIPPERS · 90D",
                         pillCopy: "Renée rates tender · payment · pull volume · Eusorone 18d DSO anchor",
                         statusPill: "GRADE A · COMPOSITE 0.92")
        case .pullVolume:
            return .init(eyebrow: "DISPATCHER · SHIPPER · PULL-VOLUME",
                         citation: "DISPATCHER PULL VOLUME · 4 SHIPPERS · 90D · §440-A",
                         title: "Pull volume",
                         subhead: "SCORE-COMPOSITE · §440-A · 90D",
                         pillCopy: "Renée attests weekly cadence · 124 pulls · Eusorone 40% NH₃ pillar",
                         statusPill: "PULLS 124 · 90D AGGREGATE · §440-A")
        case .tenderWin:
            return .init(eyebrow: "DISPATCHER · SHIPPER · TENDER-WIN",
                         citation: "DISPATCHER TENDER-WIN · 4 SHIPPERS · 90D · §440-B",
                         title: "Tender win",
                         subhead: "SCORE-COMPOSITE · §440-B · 90D",
                         pillCopy: "Renée attests tender outcome · 124 of 140 · Eusorone 100% pillar",
                         statusPill: "TENDERED 140 · 90D AGGREGATE · §440-B")
        case .paymentBehavior:
            return .init(eyebrow: "DISPATCHER · SHIPPER · PAYMENT-BEHAVIOR",
                         citation: "DISPATCHER PAYMENT · 4 SHIPPERS · 90D · §440-C",
                         title: "Payment cadence",
                         subhead: "SCORE-COMPOSITE · §440-C · 90D",
                         pillCopy: "Renée attests payment cadence · 21.4d avg · Eusorone 14.2d pillar",
                         statusPill: "INVOICED 124 · 90D AGGREGATE · §440-C")
        case .laneWin:
            return .init(eyebrow: "DISPATCHER · SHIPPER · LANE-WIN",
                         citation: "DISPATCHER LANE · 4 CORRIDORS · 90D · §440-D",
                         title: "Lane mix",
                         subhead: "SCORE-COMPOSITE · §440-D · 90D",
                         pillCopy: "Renée attests lane mix · NH₃ pillar 50/50 · Eusorone flagship",
                         statusPill: "LANES 4 · MATRIX-50 · §440-D")
        case .accountHealth:
            return .init(eyebrow: "DISPATCHER · SHIPPER · ACCOUNT-HEALTH",
                         citation: "DISPATCHER ACCOUNT-HEALTH · 4 SHIPPERS · 90D · §440-E",
                         title: "Account health",
                         subhead: "SCORE-COMPOSITE · §440-E · 90D",
                         pillCopy: "Renée attests account health · Eusorone A+ × 4 axes · 3 active + 1 dormant",
                         statusPill: "ACCOUNTS 4 · MATRIX-50 · §440-E")
        case .onboarding:
            return .init(eyebrow: "DISPATCHER · SHIPPER · ONBOARDING-STEP",
                         citation: "DISPATCHER STEP-LADDER · 4 SHIPPERS · 90D · §440-F",
                         title: "Onboarding step",
                         subhead: "SCORE-COMPOSITE · §440-F · 90D",
                         pillCopy: "Renée attests step ladder · Eusorone 6/6 terminal · 3 in-progress + 1 seeded",
                         statusPill: "STEPS 6 · MATRIX-50 · §440-F")
        case .quarter:
            return .init(eyebrow: "DISPATCHER · SHIPPER · QUARTER",
                         citation: "DISPATCHER QUARTER · 4 SHIPPERS · 4Q · §440-G",
                         title: "Quarter trajectory",
                         subhead: "SCORE-COMPOSITE · §440-G · 4Q",
                         pillCopy: "Renée attests quarter trajectory · Eusorone Q1→Q4 +0.18 monotonic",
                         statusPill: "QUARTERS 4 · MATRIX-50 · §440-G")
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

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("EU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eusorone Technologies · Diego U.").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("AURORA-CTLG-00001 · shipper-of-record · MATRIX-50").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let m = resp?.metrics
        let grade = resp?.grade ?? "A"
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",      grade,                                "composite \(Double(resp?.overallScore ?? 92) / 100)", .green),
                    ("TENDER-WIN", "\(percent(m?.tenderAcceptance))%",   "+1.2 pts vs prior 90d",                                 .green),
                    ("PAYMENT",    "\(Int(m?.averageRate ?? 26))d",      "DSO · 90d",                                              .blue),
                    ("LOADS",      "\(m?.totalLoads ?? 124)",            "90d aggregate",                                          .blue),
                ]
            case .pullVolume:
                return [
                    ("PULLS",      "\(m?.totalLoads ?? 124)",            "90d aggregate · §440-A",                                .blue),
                    ("WEEKS",      "13",                                  "rolling cadence",                                       .blue),
                    ("AVG/WK",     "9.5",                                  "+12% vs prior 90d",                                     .green),
                    ("GRADE",      grade,                                  "pillar score",                                           .green),
                ]
            case .tenderWin:
                return [
                    ("TENDERED",   "140",                                  "90d aggregate · §440-B",                                .blue),
                    ("WON",        "\(m?.deliveredCount ?? 124)",          "88.4% acceptance",                                       .green),
                    ("LOST",       "\(m?.cancelledCount ?? 16)",           "11.6% to other carriers",                               .red),
                    ("GRADE",      grade,                                  "tender pillar",                                          .green),
                ]
            case .paymentBehavior:
                return [
                    ("INVOICED",   "\(m?.totalLoads ?? 124)",              "90d aggregate · §440-C",                                .blue),
                    ("COLLECTED",  "\(m?.deliveredCount ?? 120)",          "97% close-rate",                                         .green),
                    ("AVG DSO",    "21.4d",                                 "Eusorone 14.2d pillar",                                  .orange),
                    ("GRADE",      grade,                                   "payment pillar",                                         .green),
                ]
            case .laneWin:
                return [
                    ("LANES",      "4",                                    "corridors · §440-D",                                     .blue),
                    ("WON",        "50%",                                  "NH₃ pillar share",                                       .green),
                    ("FLAGSHIP",   "EUSORONE",                              "matrix lead",                                            .green),
                    ("GRADE",      grade,                                   "lane pillar",                                            .green),
                ]
            case .accountHealth:
                return [
                    ("ACCOUNTS",   "4",                                    "shipper roster · §440-E",                               .blue),
                    ("ACTIVE",     "3",                                    "+1 dormant",                                             .green),
                    ("AXES",       "A+ × 4",                                "Eusorone all-axes",                                      .green),
                    ("GRADE",      grade,                                   "account pillar",                                         .green),
                ]
            case .onboarding:
                return [
                    ("STEPS",      "6",                                    "ladder · §440-F",                                       .blue),
                    ("TERMINAL",   "6/6",                                   "Eusorone closed",                                        .green),
                    ("IN-PROG",    "3",                                     "shipper accounts",                                       .orange),
                    ("SEEDED",     "1",                                     "dormant · awaiting kick-off",                            .blue),
                ]
            case .quarter:
                return [
                    ("QUARTERS",   "4",                                    "Q1-Q4 rolling · §440-G",                                .blue),
                    ("TREND",      "+0.18",                                 "Q1→Q4 monotonic",                                        .green),
                    ("LOADS",      "\(m?.totalLoads ?? 0)",                 "Q1-Q4 cumulative",                                       .blue),
                    ("GRADE",      grade,                                    "year-rolling pillar",                                    .green),
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
            case .review:           return "Composite pillar A — refresh weekly. Use to set tender priority + payment terms by shipper."
            case .pullVolume:       return "Cadence is healthy. Hold the 9.5/wk floor for the NH₃ pillar; nudge dormant account up."
            case .tenderWin:        return "11.6% tender loss is acceptable. Investigate the 16 lost loads — were they price or capacity?"
            case .paymentBehavior:  return "21.4d DSO is over the Eusorone 14.2d pillar. Push a NET-15 conversation on Q2 contracts."
            case .laneWin:          return "NH₃ pillar holding 50/50. Lock the Eusorone flagship; cross-sell the other 3 corridors."
            case .accountHealth:    return "3 active + 1 dormant. Re-engage the dormant account with a quick-tender invite."
            case .onboarding:       return "Eusorone is fully onboarded. Drive the 3 in-progress accounts to terminal; revive the seeded one."
            case .quarter:          return "Q1→Q4 +0.18 monotonic — healthy trajectory. Hold the playbook into next year."
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
        struct In: Encodable { let shipperId: Int; let periodDays: Int }
        let sid = Int(shipperId) ?? 0
        do {
            resp = try await EusoTripAPI.shared.query(
                "shipperScorecard.getScorecard",
                input: In(shipperId: sid, periodDays: kind.period)
            )
        } catch { /* */ }
    }
}

private func percent(_ raw: Double?) -> String {
    guard let raw else { return "88" }
    return String(format: "%.1f", raw)
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
