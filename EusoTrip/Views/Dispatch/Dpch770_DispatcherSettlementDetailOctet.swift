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

import SwiftUI

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
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let statusPill: String
}

private extension DispatcherSettlementKind {
    var config: DSConfig {
        switch self {
        case .review:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · REVIEW",
                         citation: "DISPATCHER REVIEW · SETTLEMENT STREAMS · 90D",
                         title: "Settlement review",
                         subhead: "AURORA-CTLG-00001 · 4 CLASSES · 90D",
                         pillCopy: "Renée rates DSO · quick-pay velocity · adjustments · Eusorone NH₃ settlement anchor",
                         statusPill: "GRADE A · COMPOSITE 0.93")
        case .dso:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · DSO",
                         citation: "DISPATCHER DSO · 4 CLASSES · 90D · §500-A",
                         title: "DSO axis",
                         subhead: "SCORE-COMPOSITE · §500-A · 90D",
                         pillCopy: "Renée rates per-class DSO · 11.4d fleet · EUSORONE 4.2d floor",
                         statusPill: "DSO 11.4d · EUSORONE FLOOR 4.2d")
        case .qpayVelocity:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · QPAY VELOCITY",
                         citation: "DISPATCHER QPAY · 4 CLASSES · 90D · §500-B",
                         title: "QPAY velocity",
                         subhead: "SCORE-COMPOSITE · §500-B · 90D",
                         pillCopy: "Renée rates per-class quick-pay velocity · 0.88 fleet · EUSORONE 1.00 ceiling",
                         statusPill: "QPAY 0.88 · EUSORONE CEILING 1.00")
        case .openLedger:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · OPEN LEDGER",
                         citation: "DISPATCHER OPEN LEDGER · 4 CLASSES · 90D · §500-C",
                         title: "Open ledger",
                         subhead: "SCORE-COMPOSITE · §500-C · 90D",
                         pillCopy: "Renée rates per-class balance · $48.7K fleet · EUSORONE $0 floor",
                         statusPill: "OPEN $48.7K · EUSORONE FLOOR $0")
        case .cleanRate:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · CLEAN RATE",
                         citation: "DISPATCHER CLEAN RATE · 4 CLASSES · 90D · §500-D",
                         title: "Clean rate",
                         subhead: "SCORE-COMPOSITE · §500-D · 90D",
                         pillCopy: "Renée reconciles per-class ratios · 0.96 fleet · EUSORONE 1.00 ceiling",
                         statusPill: "CLEAN 0.96 · EUSORONE CEILING 1.00")
        case .onboarding:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · ONBOARDING",
                         citation: "DISPATCHER ONBOARDING · 4 CLASSES · 90D · §500-E",
                         title: "Onboarding",
                         subhead: "SCORE-COMPOSITE · §500-E · 90D",
                         pillCopy: "Renée onboards per-class steps · 4.05 fleet · EUSORONE 5/5 ceiling",
                         statusPill: "STEPS 4.05 · EUSORONE 5/5 TERMINAL")
        case .compliance:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · COMPLIANCE",
                         citation: "DISPATCHER COMPLIANCE · 4 CLASSES · 90D · §500-F",
                         title: "Compliance",
                         subhead: "SCORE-COMPOSITE · §500-F · 90D",
                         pillCopy: "Renée audits per-class compliance rows · 4.15 fleet · EUSORONE 5/5 ceiling",
                         statusPill: "ROWS 4.15 · EUSORONE 5/5 CLEAN")
        case .quarter:
            return .init(eyebrow: "DISPATCHER · SETTLEMENT · TRAJECTORY",
                         citation: "DISPATCHER SETTLEMENT TRAJECTORY · 4 QUARTERS · YEAR 2026 · §500-G",
                         title: "Quarter trajectory",
                         subhead: "SCORE-COMPOSITE · §500-G · YEAR 2026",
                         pillCopy: "Renée rates year-cadence · 0.95 fleet target · EUSORONE 4Q ceiling streak",
                         statusPill: "YEAR 0.95 · EUSORONE 4Q CEILING")
        }
    }
}

private struct DispatcherSettlementShell<Content: View>: View {
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

private struct DispatcherSettlementBody: View {
    let kind: DispatcherSettlementKind

    @Environment(\.palette) private var palette
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
        .refreshable { await load() }
    }

    private func header(_ c: DSConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: DSConfig) -> some View {
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
                    .overlay(Image(systemName: "dollarsign.circle.fill").font(.system(size: 14)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aurora Freight Lines · Settlement Streams").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("AURORA-CTLG-00001 · 4 classes · 184 events · EUSORONE TIER 1 DEDICATED").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let s = stats
        let openLedger = (s?.pending ?? 0) > 0 ? "$\(Int(s!.pending! / 1000))K" : "$48.7K"
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                return [
                    ("GRADE",     "A",                                "composite 0.93",            .green),
                    ("DSO",       "11.4d",                             "fleet · EUSO 4.2d floor",  .green),
                    ("SETTLED",   currencyK(s?.totalSettled ?? 0, fallback: 148.2), "90d gross",   .blue),
                    ("EVENTS",    "\(s?.total ?? 184)",                "90d aggregate",            .blue),
                ]
            case .dso:
                return [
                    ("DSO",       "11.4d",                             "fleet · §500-A",           .green),
                    ("EUSO",      "4.2d",                              "floor · 90d",             .green),
                    ("EVENTS",    "\(s?.total ?? 184)",                "90d · cleared",            .blue),
                    ("GRADE",     "A",                                  "DSO pillar",              .green),
                ]
            case .qpayVelocity:
                return [
                    ("QPAY",      "0.88",                               "velocity · §500-B",        .green),
                    ("CEILING",   "1.00",                                "EUSORONE peak",          .green),
                    ("VOLUME",    currencyK(s?.totalPaid ?? 0, fallback: 148.2), "90d via QPAY",    .blue),
                    ("GRADE",     "A",                                    "velocity pillar",        .green),
                ]
            case .openLedger:
                return [
                    ("OPEN",      openLedger,                              "ledger · §500-C",       .orange),
                    ("EUSO",      "$0",                                     "floor · 90d",          .green),
                    ("EVENTS",    "\(s?.total ?? 184)",                      "in-flight",          .blue),
                    ("GRADE",     "A",                                        "balance pillar",     .green),
                ]
            case .cleanRate:
                return [
                    ("CLEAN",     "0.96",                                     "rate · §500-D",       .green),
                    ("CEILING",   "1.00",                                      "EUSORONE peak",     .green),
                    ("ADJUST",    "3.8%",                                       "fleet · 90d",      .orange),
                    ("GRADE",     "A",                                            "ratio pillar",   .green),
                ]
            case .onboarding:
                return [
                    ("STEPS",     "4.05",                                          "fleet · §500-E",  .green),
                    ("CEILING",   "5/5",                                            "EUSORONE peak", .green),
                    ("OPEN-IP",   "3",                                                "in-progress", .orange),
                    ("GRADE",     "A",                                                  "steps pillar", .green),
                ]
            case .compliance:
                return [
                    ("ROWS",      "4.15",                                                "fleet · §500-F", .green),
                    ("CEILING",   "5/5",                                                  "EUSORONE peak", .green),
                    ("AUDIT",     "0 OPEN",                                                "90d · clean",  .green),
                    ("GRADE",     "A",                                                      "compliance pillar", .green),
                ]
            case .quarter:
                return [
                    ("YEAR-AVG",  "0.95",                                                    "EOY · §500-G", .green),
                    ("CEILING",   "EUSORONE",                                                  "4Q streak",   .green),
                    ("EVENTS",    "\(s?.total ?? 184)",                                          "year",       .blue),
                    ("GRADE",     "A",                                                              "year pillar", .green),
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
            case .review:        return "Composite A · EUSORONE NH₃ settlement anchor holding 4.2d DSO floor. Refresh weekly."
            case .dso:           return "11.4d fleet DSO is healthy. Push TR-201 / TR-301 to match EUSORONE's 4.2d floor."
            case .qpayVelocity:  return "0.88 QPAY velocity — accelerate the slow accounts via the next NACHA window."
            case .openLedger:    return "$48.7K open across 4 classes. Drain via QPAY in the next NACHA cycle."
            case .cleanRate:     return "Clean rate 0.96. Investigate the 3.8% adjustment band — most likely lumper reconciliation."
            case .onboarding:    return "EUSORONE 5/5 closed; bring the 3 in-progress accounts to terminal before Q2 cut."
            case .compliance:    return "Zero open audits. Quarterly compliance row clean — archive Q1 evidence pack."
            case .quarter:       return "Year-rolling 0.95 target. EUSORONE 4Q streak — copy playbook to next 3 dedicated accounts."
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

private func currencyK(_ value: Double, fallback: Double) -> String {
    let v = value > 0 ? value : fallback * 1000
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
