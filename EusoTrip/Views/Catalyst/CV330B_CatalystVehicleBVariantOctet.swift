//
//  CV330B_CatalystVehicleBVariantOctet.swift
//  EusoTrip — Catalyst · Vehicle B-variant deep-drill octet (330B-337B).
//
//  Pixel-match to:
//    330B Catalyst Vehicle Scorecard Axis Detail
//    331B Catalyst Vehicle Profile Tier Detail
//    332B Catalyst Vehicle Document Detail
//    333B Catalyst Vehicle Analytic Detail
//    334B Catalyst Vehicle Settlement Detail
//    335B Catalyst Vehicle Onboarding Step Detail
//    336B Catalyst Vehicle Compliance Row Detail
//    337B Catalyst Vehicle Quarter Detail
//
//  B-variants of the CV330-CV336 octet — same Peterbilt 579 owner-op
//  but one level deeper: each surfaces a specific row identifier
//  (SCORE-260427-COMPOSITE-PB579 / TIER-GOLD / DOC-HM126F /
//   PERF-MPG / ALLOC-A38FB12C7E / STEP-CVSA / COMP-HM126F /
//   PERF-Q1ROLL). All 8 share `CatalystVehicleBBody`. Body reads
//  `fleet.getFleetStats` for fleet-side metrics + surfaces the
//  per-row drill identity. Bottom nav frozen.
//

import SwiftUI

private struct CVBFleetStats: Decodable, Hashable {
    let totalVehicles: Int?
    let utilization: Int?
    let avgMpg: Double?
    let inMaintenance: Int?
}

enum CatalystVehicleBKind: String {
    case scoreAxis, profileTier, document, analytic, settlement, onboarding, compliance, quarter
}

private struct CVBConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let rowId: String           // SCORE-260427-COMPOSITE-PB579 etc.
    let statusBadge: String     // PUBLISHED / DUE / EXPIRED / CLOSED
    let statusColor: Color
    let grade: String           // "A" / "G"
}

private extension CatalystVehicleBKind {
    var config: CVBConfig {
        switch self {
        case .scoreAxis:
            return .init(eyebrow: "CATALYST · VEHICLE · SCORECARD AXIS",
                         citation: "§9.4 · LIVE",
                         title: "Axis detail",
                         subhead: "TRK-001-PB579 · §9.4 · LIVE",
                         pillCopy: "Catalyst rates asset · same companyId both sides · clean §9.4 vehicle books",
                         rowId: "SCORE-260427-COMPOSITE-PB579", statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "A")
        case .profileTier:
            return .init(eyebrow: "CATALYST · VEHICLE · TIER",
                         citation: "§13.4 · LIVE",
                         title: "Tier detail",
                         subhead: "TRK-001-PB579 · §13.4 · LIVE",
                         pillCopy: "Catalyst rates asset · same companyId both sides · clean §13.4 tier criteria",
                         rowId: "TIER-260427-GOLD-PB579", statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "G")
        case .document:
            return .init(eyebrow: "CATALYST · VEHICLE · DOCUMENT",
                         citation: "§107.601 · MISSING",
                         title: "Document detail",
                         subhead: "TRK-001-PB579 · §107.601 · MISSING",
                         pillCopy: "Catalyst archives vehicle docs · same companyId both sides · clean §107.601 hazmat registration",
                         rowId: "DOC-260427-HM126F-PB579", statusBadge: "MISSING · ACTION", statusColor: .red, grade: "A")
        case .analytic:
            return .init(eyebrow: "CATALYST · VEHICLE · ANALYTIC",
                         citation: "§9.4 · LIVE",
                         title: "Analytic detail",
                         subhead: "TRK-001-PB579 · §9.4 · LIVE",
                         pillCopy: "Catalyst tracks asset KPIs · same companyId both sides · clean §9.4 mpg-index record",
                         rowId: "PERF-260427-MPG-PB579", statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "A")
        case .settlement:
            return .init(eyebrow: "CATALYST · VEHICLE · SETTLEMENT",
                         citation: "§168(k) CLEAN BOOKS · POD SIGNED",
                         title: "Settlement detail",
                         subhead: "TRK-001-PB579 · LD-…7E · POD SIGNED",
                         pillCopy: "Catalyst earns on asset · same companyId both sides · clean depreciation books",
                         rowId: "ALLOC-260427-A38FB12C7E", statusBadge: "DUE · POD SIGNED", statusColor: .green, grade: "A")
        case .onboarding:
            return .init(eyebrow: "CATALYST · ASSET · STEP DETAIL",
                         citation: "§396.17 · EXPIRED",
                         title: "Step detail",
                         subhead: "TRK-001-PB579 · §396.17 · EXPIRED",
                         pillCopy: "Catalyst onboards asset · same companyId both sides · clean §396 periodic-inspection file",
                         rowId: "STEP-260427-CVSA-PB001", statusBadge: "EXPIRED · ACTION", statusColor: .red, grade: "A")
        case .compliance:
            return .init(eyebrow: "CATALYST · VEHICLE · COMPLIANCE ROW",
                         citation: "§107.601 · MISSING",
                         title: "Compliance row",
                         subhead: "TRK-001-PB579 · §107.601 · MISSING",
                         pillCopy: "Catalyst monitors asset · same companyId both sides · clean §397 hazmat-transport pool",
                         rowId: "COMP-260427-HM126F-PB579", statusBadge: "MISSING · ACTION", statusColor: .red, grade: "A")
        case .quarter:
            return .init(eyebrow: "CATALYST · VEHICLE · QUARTER DETAIL",
                         citation: "Q1-2026 · CLOSED",
                         title: "Quarter detail",
                         subhead: "TRK-001-PB579 · Q1-2026 · CLOSED",
                         pillCopy: "Catalyst archives Q1 asset rollup · same companyId both sides · clean §168 depreciation closed quarter",
                         rowId: "PERF-260331-Q1ROLL-PB579", statusBadge: "CLOSED · QC LOGGED", statusColor: .green, grade: "A")
        }
    }
}

private struct CatalystVehicleBShell<Content: View>: View {
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

private struct CatalystVehicleBBody: View {
    let kind: CatalystVehicleBKind

    @Environment(\.palette) private var palette
    @State private var stats: CVBFleetStats?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                rowCard(c)
                identityRow
                kpiGrid(c)
                nextStepCard(c)
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ c: CVBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CVBConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · \(c.citation)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rowCard(_ c: CVBConfig) -> some View {
        LifecycleCard {
            HStack(spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(c.grade).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
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
                    .overlay(Text("PB").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Peterbilt 579 · 2022 · TRK-001-PB579").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("Eusotrans LLC · owner-op · titled 2024-08-04").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CVBConfig) -> some View {
        let s = stats
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scoreAxis:
                return [
                    ("GRADE",    c.grade,                                       "composite axis",            .green),
                    ("UTIL",     "\(s?.utilization ?? 84)%",                    "fleet · live · §9.4",       .green),
                    ("MPG",      fmtCVBMpg(s?.avgMpg),                            "live fuel · §9.4",        .blue),
                    ("STATE",    "LIVE",                                          c.statusBadge,             .green),
                ]
            case .profileTier:
                return [
                    ("TIER",     "GOLD",                                           "Eusotrans · LD-7C3A asset", .green),
                    ("CRITERIA", "§13.4",                                            "tier published",         .blue),
                    ("STATE",    "LIVE",                                              c.statusBadge,           .green),
                    ("EFFECT",   "+0.06",                                              "pillar boost vs Silver", .green),
                ]
            case .document:
                return [
                    ("DOC",      "HM-126F",                                              "hazmat registration",  .red),
                    ("STATE",    "MISSING",                                                "§107.601 · action",  .red),
                    ("RUNWAY",   "0d",                                                       "renew · urgent",   .red),
                    ("OWNER",    "Eusotrans",                                                 "to file by EOD",  .blue),
                ]
            case .analytic:
                return [
                    ("MPG",      fmtCVBMpg(s?.avgMpg),                                          "90d · live",     .blue),
                    ("IDX",      "+0.12",                                                       "vs fleet mean",  .green),
                    ("STATE",    "LIVE",                                                         c.statusBadge,   .green),
                    ("PILLAR",   "§9.4",                                                          "MPG index pillar", .blue),
                ]
            case .settlement:
                return [
                    ("AMOUNT",   "$1,320",                                                          "this allocation",  .green),
                    ("CHAIN",    "LD-...7E",                                                         "POD signed",     .green),
                    ("STATE",    "DUE",                                                                "NET-30 due",     .orange),
                    ("BOOK",     "§168(k)",                                                              "clean books",  .blue),
                ]
            case .onboarding:
                return [
                    ("STEP",     "CVSA",                                                                  "periodic inspection",  .red),
                    ("STATE",    "EXPIRED",                                                                "§396.17 · action",   .red),
                    ("RUNWAY",   "0d",                                                                      "renew · urgent",    .red),
                    ("OWNER",    "Eusotrans",                                                                "to schedule",      .blue),
                ]
            case .compliance:
                return [
                    ("ROW",      "HM-126F",                                                                   "hazmat-transport row", .red),
                    ("STATE",    "MISSING",                                                                    "§107.601 · pool",   .red),
                    ("POOL",     "§397",                                                                        "transport pillar", .blue),
                    ("OWNER",    "Eusotrans",                                                                    "to file",          .blue),
                ]
            case .quarter:
                return [
                    ("Q1",       "CLOSED",                                                                       "2026-03-31",        .green),
                    ("ROLLUP",   "$14,820",                                                                       "gross · 9 loads",  .green),
                    ("BOOK",     "§168",                                                                           "depreciation closed", .blue),
                    ("STATE",    "QC LOGGED",                                                                      c.statusBadge,     .green),
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

    private func nextStepCard(_ c: CVBConfig) -> some View {
        let copy: String = {
            switch kind {
            case .scoreAxis:   return "Composite axis grade A. Pinned to §9.4 vehicle books — refresh weekly with the next QC cycle."
            case .profileTier: return "Gold tier (§13.4) holds +0.06 pillar boost. Reconfirm criteria on Q2 baseline."
            case .document:    return "Hazmat HM-126F registration is missing. File §107.601 by EOD to clear the asset for the next NH₃ pull."
            case .analytic:    return "MPG index +0.12 vs fleet mean. Hold the cadence — owner-op driving discipline is the lever."
            case .settlement:  return "Allocation A38FB12C7E at $1,320, POD signed. NET-30 wires next; advance-eligible 1.5%/5D."
            case .onboarding:  return "CVSA periodic inspection expired (§396.17). Schedule mechanic + DOT lane immediately."
            case .compliance:  return "Hazmat-transport pool row HM-126F missing. Pair with the §107.601 doc filing above."
            case .quarter:     return "Q1 closed 2026-03-31 with $14,820 gross · 9 loads. Q1 1099-NEC ready for tax cabinet."
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
        do { stats = try await EusoTripAPI.shared.queryNoInput("fleet.getFleetStats") } catch { /* */ }
    }
}

private func fmtCVBMpg(_ raw: Double?) -> String {
    let v = raw ?? 6.8
    return String(format: "%.1f", v > 0 ? v : 6.8)
}

// MARK: - Screens (CV330B-CV337B)

struct CatalystVehicleScoreAxisScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .scoreAxis) } }
}
struct CatalystVehicleProfileTierScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .profileTier) } }
}
struct CatalystVehicleDocumentDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .document) } }
}
struct CatalystVehicleAnalyticDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .analytic) } }
}
struct CatalystVehicleSettlementDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .settlement) } }
}
struct CatalystVehicleStepDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .onboarding) } }
}
struct CatalystVehicleComplianceRowScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .compliance) } }
}
struct CatalystVehicleQuarterDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystVehicleBShell(theme: theme) { CatalystVehicleBBody(kind: .quarter) } }
}

// MARK: - Previews

#Preview("CV330B Axis · Dark")    { CatalystVehicleScoreAxisScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV331B Tier · Light")   { CatalystVehicleProfileTierScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV332B Doc · Dark")     { CatalystVehicleDocumentDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV333B Analytic · Light") { CatalystVehicleAnalyticDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV334B Settle · Dark")  { CatalystVehicleSettlementDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV335B Step · Light")   { CatalystVehicleStepDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV336B Comp · Dark")    { CatalystVehicleComplianceRowScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV337B Q1 · Light")     { CatalystVehicleQuarterDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
