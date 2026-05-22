//
//  CV320B_CatalystDriverBVariantOctet.swift
//  EusoTrip — Catalyst · Driver B-variant deep-drill octet (320B-327B).
//
//  Pixel-match to:
//    320B Catalyst Scorecard Axis Detail            (§9.1)
//    321B Catalyst Profile Tier Detail              (§13 · GOLD)
//    322B Catalyst Document Detail                  (§382.301 · MISSING)
//    323B Catalyst Driver Analytic Detail           (§395.8 · LIVE)
//    324B Catalyst Driver Settlement Detail         (POD SIGNED · $1,805)
//    325B Catalyst Driver Onboarding Step Detail    (§382 · MISSING)
//    326B Catalyst Compliance Row Detail            (§382.305 · MISSING)
//    327B Catalyst Driver Quarter Detail            (Q1 · 94.0%)
//
//  Driver counterparts to CV330B-CV337B. Cast: ME · Michael Eusorone ·
//  DR-001-EUSO · Eusotrans LLC. Single bundled file. Body reads
//  `drivers.getPerformanceMetrics`. Bottom nav frozen.
//

import SwiftUI

private struct CDBMetrics: Decodable, Hashable {
    let driverId: String?
    let metrics: M?
    struct M: Decodable, Hashable {
        let totalLoads: Int?
        let onTimeDeliveryRate: Int?
        let safetyScore: Double?
        let hosCompliance: Int?
        let inspectionPassRate: Int?
    }
}

enum CatalystDriverBKind: String {
    case scoreAxis, profileTier, document, analytic, settlement, onboarding, compliance, quarter
}

private struct CDBConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let rowId: String
    let statusBadge: String
    let statusColor: Color
    let grade: String
}

private extension CatalystDriverBKind {
    var config: CDBConfig {
        switch self {
        case .scoreAxis:
            return .init(eyebrow: "CATALYST · DRIVER · SCORECARD AXIS",
                         citation: "§9.1 · LIVE",
                         title: "Axis detail",
                         subhead: "DR-001-EUSO · §9.1 · LIVE",
                         pillCopy: "Catalyst rates driver · same companyId both sides · clean §9.1 composite books",
                         rowId: "SCORE-260427-COMPOSITE-DR001",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "A+")
        case .profileTier:
            return .init(eyebrow: "CATALYST · DRIVER · TIER",
                         citation: "§13 · LIVE",
                         title: "Tier detail",
                         subhead: "DR-001-EUSO · §13 · LIVE",
                         pillCopy: "Catalyst rates driver · same companyId both sides · clean §13 tier criteria",
                         rowId: "TIER-260427-GOLD-DR001",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "G")
        case .document:
            return .init(eyebrow: "CATALYST · DRIVER · DOCUMENT",
                         citation: "§382.301 · MISSING",
                         title: "Document detail",
                         subhead: "DR-001-EUSO · §382.301 · MISSING",
                         pillCopy: "Catalyst archives driver docs · same companyId both sides · clean §382.301 pre-employment file",
                         rowId: "DOC-260427-DRUG-DR001",
                         statusBadge: "MISSING · ACTION", statusColor: .red, grade: "A+")
        case .analytic:
            return .init(eyebrow: "CATALYST · DRIVER · ANALYTIC",
                         citation: "§395.8 · LIVE",
                         title: "Analytic detail",
                         subhead: "DR-001-EUSO · §395.8 · LIVE",
                         pillCopy: "Catalyst tracks driver KPIs · same companyId both sides · clean §395.8 ELD record",
                         rowId: "PERF-260427-OTD-DR001",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "A+")
        case .settlement:
            return .init(eyebrow: "CATALYST · DRIVER · SETTLEMENT",
                         citation: "POD SIGNED · ACH ····6411",
                         title: "Settlement detail",
                         subhead: "DR-001-EUSO · LD-…7E · POD SIGNED",
                         pillCopy: "Catalyst pays driver · same companyId both sides · clean settlement line items",
                         rowId: "SET-260427-A38FB12C7E",
                         statusBadge: "DUE · POD SIGNED", statusColor: .green, grade: "A+")
        case .onboarding:
            return .init(eyebrow: "CATALYST · DRIVER · STEP DETAIL",
                         citation: "§382.301 · MISSING",
                         title: "Step detail",
                         subhead: "DR-001-EUSO · §382.301 · MISSING",
                         pillCopy: "Catalyst onboards driver · same companyId both sides · clean §382 controlled-substances file",
                         rowId: "STEP-260427-DRUG-DR001",
                         statusBadge: "MISSING · ACTION", statusColor: .red, grade: "A+")
        case .compliance:
            return .init(eyebrow: "CATALYST · DRIVER · COMPLIANCE ROW",
                         citation: "§382.305 · MISSING",
                         title: "Compliance row",
                         subhead: "DR-001-EUSO · §382.305 · MISSING",
                         pillCopy: "Catalyst monitors driver · same companyId both sides · clean §382.305 random-testing pool",
                         rowId: "COMP-260427-CSAPP-DR001",
                         statusBadge: "MISSING · ACTION", statusColor: .red, grade: "A+")
        case .quarter:
            return .init(eyebrow: "CATALYST · DRIVER · QUARTER DETAIL",
                         citation: "Q1-2026 · CLOSED",
                         title: "Quarter detail",
                         subhead: "DR-001-EUSO · Q1-2026 · CLOSED",
                         pillCopy: "Catalyst archives Q1 driver rollup · same companyId both sides · clean Schedule C closed quarter",
                         rowId: "PERF-260331-Q1ROLL-DR001",
                         statusBadge: "CLOSED · RECONCILED", statusColor: .green, grade: "A+")
        }
    }
}

private struct CatalystDriverBShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",          isCurrent: false),
                          NavSlot(label: "Fleet", systemImage: "truck.box.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct CatalystDriverBBody: View {
    let kind: CatalystDriverBKind

    @Environment(\.palette) private var palette
    @State private var resp: CDBMetrics?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                rowCard(c)
                identityRow
                kpiGrid(c)
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ c: CDBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CDBConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · \(c.citation)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rowCard(_ c: CDBConfig) -> some View {
        LifecycleCard {
            HStack(spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(c.grade).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.rowId).font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(c.statusBadge).font(.caption2).foregroundStyle(c.statusColor)
                }
                Spacer()
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text("ME").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Michael Eusorone · DR-001-EUSO").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("Eusotrans LLC · hired 2025-04-15 · ACH ····6411").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CDBConfig) -> some View {
        let m = resp?.metrics
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scoreAxis:
                return [
                    ("GRADE",    c.grade,                                "composite axis · §9.1", .green),
                    ("ON-TIME",  "\(m?.onTimeDeliveryRate ?? 95)%",       "+0.6 vs prior 90d",   .green),
                    ("ELD",      "\(m?.hosCompliance ?? 100)%",            "§395.8 clean",       .green),
                    ("STATE",    "LIVE",                                    c.statusBadge,        .green),
                ]
            case .profileTier:
                return [
                    ("TIER",     "GOLD",                                     "Eusotrans · DR-001",  .green),
                    ("CRITERIA", "§13",                                       "criteria met",      .blue),
                    ("STATE",    "LIVE",                                       c.statusBadge,      .green),
                    ("EFFECT",   "+0.08",                                       "pillar boost",    .green),
                ]
            case .document:
                return [
                    ("DOC",      "DRUG SCREEN",                                "§382.301 · pre-employ", .red),
                    ("STATE",    "MISSING",                                      "action · EOD",      .red),
                    ("RUNWAY",   "0d",                                              "renew · urgent", .red),
                    ("OWNER",    "Eusotrans",                                       "to file",       .blue),
                ]
            case .analytic:
                return [
                    ("ON-TIME",  "\(m?.onTimeDeliveryRate ?? 94)%",                  "delivery pillar",  .green),
                    ("ELD",      "§395.8",                                            "live record",    .blue),
                    ("STATE",    "LIVE",                                                c.statusBadge,  .green),
                    ("PASS",     "\(m?.inspectionPassRate ?? 100)%",                    "inspection · §396",   .green),
                ]
            case .settlement:
                return [
                    ("AMOUNT",   "$1,805",                                                "this allocation",  .green),
                    ("CHAIN",    "LD-...7E",                                              "POD signed",       .green),
                    ("STATE",    "DUE",                                                    "ACH ····6411",    .orange),
                    ("BOOK",     "§168",                                                    "clean books",    .blue),
                ]
            case .onboarding:
                return [
                    ("STEP",     "DRUG SCREEN",                                              "§382 controlled-sub",  .red),
                    ("STATE",    "MISSING",                                                    "action · urgent",     .red),
                    ("RUNWAY",   "0d",                                                          "schedule · today",  .red),
                    ("OWNER",    "Eusotrans",                                                    "lab booking",       .blue),
                ]
            case .compliance:
                return [
                    ("ROW",      "CSAPP",                                                         "random-testing pool",  .red),
                    ("STATE",    "MISSING",                                                       "§382.305 · action",   .red),
                    ("POOL",     "§382.305",                                                       "random-test pillar", .blue),
                    ("OWNER",    "Eusotrans",                                                      "to file",          .blue),
                ]
            case .quarter:
                return [
                    ("Q1",       "CLOSED",                                                         "2026-03-31",        .green),
                    ("OTP",      "94.0%",                                                          "Q1 on-time",       .green),
                    ("SCHEDULE", "C",                                                               "1099-NEC ready",   .blue),
                    ("STATE",    "RECONCILED",                                                      c.statusBadge,      .green),
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
            case .scoreAxis:   return "Composite axis A+. Pinned to §9.1 driver books — refresh weekly with the next QC cycle."
            case .profileTier: return "Gold tier (§13) holds +0.08 pillar boost. Reconfirm criteria on Q2 baseline."
            case .document:    return "Pre-employment drug screen (§382.301) missing. File by EOD to clear driver for next NH₃ pull."
            case .analytic:    return "On-time 94%, §395.8 ELD clean. Hold the cadence — Schedule C records auto-feed quarter close."
            case .settlement:  return "Allocation A38FB12C7E at $1,805, POD signed. NET-30 wires next via ACH ····6411."
            case .onboarding:  return "Drug screen step (§382) missing — schedule lab booking today."
            case .compliance:  return "Random-testing pool row (§382.305) missing. Pair with the §382.301 doc filing above."
            case .quarter:     return "Q1 closed 2026-03-31 at 94.0% OTP. Schedule C ready for tax cabinet archive."
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
        struct In: Encodable { let driverId: String; let period: String }
        do { resp = try await EusoTripAPI.shared.query("drivers.getPerformanceMetrics", input: In(driverId: "0", period: "quarter")) } catch { /* */ }
    }
}

// MARK: - Screens (320B-327B)

struct CatalystDriverScoreAxisScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystDriverBShell(theme: theme) { CatalystDriverBBody(kind: .scoreAxis) } }
}
struct CatalystDriverProfileTierScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystDriverBShell(theme: theme) { CatalystDriverBBody(kind: .profileTier) } }
}
struct CatalystDriverDocumentDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystDriverBShell(theme: theme) { CatalystDriverBBody(kind: .document) } }
}
struct CatalystDriverAnalyticDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystDriverBShell(theme: theme) { CatalystDriverBBody(kind: .analytic) } }
}
struct CatalystDriverSettlementDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystDriverBShell(theme: theme) { CatalystDriverBBody(kind: .settlement) } }
}
struct CatalystDriverStepDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystDriverBShell(theme: theme) { CatalystDriverBBody(kind: .onboarding) } }
}
struct CatalystDriverComplianceRowScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystDriverBShell(theme: theme) { CatalystDriverBBody(kind: .compliance) } }
}
struct CatalystDriverQuarterDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystDriverBShell(theme: theme) { CatalystDriverBBody(kind: .quarter) } }
}

// MARK: - Previews

#Preview("320B Axis · Dark")     { CatalystDriverScoreAxisScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("321B Tier · Light")    { CatalystDriverProfileTierScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("322B Doc · Dark")      { CatalystDriverDocumentDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("323B Analytic · Light"){ CatalystDriverAnalyticDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("324B Settle · Dark")   { CatalystDriverSettlementDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("325B Step · Light")    { CatalystDriverStepDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("326B Comp · Dark")     { CatalystDriverComplianceRowScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("327B Q1 · Light")      { CatalystDriverQuarterDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
