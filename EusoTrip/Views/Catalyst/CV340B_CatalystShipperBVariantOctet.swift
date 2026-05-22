//
//  CV340B_CatalystShipperBVariantOctet.swift
//  EusoTrip — Catalyst · Shipper B-variant deep-drill octet (340B-347B).
//
//  Pixel-match to:
//    340B Catalyst Shipper Scorecard Axis Detail   (§9.5 · COMPOSITE)
//    341B Catalyst Shipper Profile Tier Detail     (§13.5 · GOLD)
//    342B Catalyst Shipper Document Detail
//    343B Catalyst Shipper Analytic Detail
//    344B Catalyst Shipper Settlement Detail       (NET-30 12D · INV-A38FB12C7E)
//    345B Catalyst Shipper Onboarding Step Detail
//    346B Catalyst Shipper Compliance Row Detail
//    347B Catalyst Shipper Quarter Detail          (PERF-Q1ROLL-EUSORONE)
//
//  Closes the Catalyst B-variant set (24/24). Cast: DU · Diego Usoro ·
//  Eusorone Technologies · SHIP-001-EUSORONE · EIN 87-3104952.
//  Body reads `shipperScorecard.getScorecard`. Bottom nav frozen.
//

import SwiftUI

private struct CSBResp: Decodable, Hashable {
    let shipperId: Int?
    let overallScore: Int?
    let grade: String?
    let metrics: M?
    struct M: Decodable, Hashable {
        let tenderAcceptance: Double?
        let totalLoads: Int?
        let averageRate: Double?
    }
}

enum CatalystShipperBKind: String {
    case scoreAxis, profileTier, document, analytic, settlement, onboarding, compliance, quarter
}

private struct CSBConfig {
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

private extension CatalystShipperBKind {
    var config: CSBConfig {
        switch self {
        case .scoreAxis:
            return .init(eyebrow: "CATALYST · CUSTOMER · SCORECARD AXIS",
                         citation: "§9.5 · LIVE",
                         title: "Axis detail",
                         subhead: "SHIP-001-EUSORONE · §9.5 · LIVE",
                         pillCopy: "Catalyst rates shipper · same companyId both sides · clean §9.5 shipper books",
                         rowId: "SCORE-260427-COMPOSITE-EUSORONE",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "A")
        case .profileTier:
            return .init(eyebrow: "CATALYST · SHIPPER · TIER",
                         citation: "§13.5 · LIVE",
                         title: "Tier detail",
                         subhead: "SHIP-001-EUSORONE · §13.5 · LIVE",
                         pillCopy: "Catalyst rates shipper · same companyId both sides · clean §13.5 tier criteria",
                         rowId: "TIER-260427-GOLD-SHIP001",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "G")
        case .document:
            return .init(eyebrow: "CATALYST · CUSTOMER · DOCUMENT",
                         citation: "§387.7 · CURRENT",
                         title: "Document detail",
                         subhead: "SHIP-001-EUSORONE · §387.7 · COI on file",
                         pillCopy: "Catalyst archives shipper docs · same companyId both sides · clean §387.7 COI cabinet",
                         rowId: "DOC-260427-COI-SHIP001",
                         statusBadge: "ON FILE · CURRENT", statusColor: .green, grade: "A")
        case .analytic:
            return .init(eyebrow: "CATALYST · CUSTOMER · ANALYTIC",
                         citation: "§9.5 · LIVE",
                         title: "Analytic detail",
                         subhead: "SHIP-001-EUSORONE · §9.5 · LIVE",
                         pillCopy: "Catalyst tracks payor KPIs · same companyId · clean tender-win + DSO + lane mix",
                         rowId: "PERF-260427-DSO-SHIP001",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green, grade: "A")
        case .settlement:
            return .init(eyebrow: "CATALYST · CUSTOMER · SETTLEMENT",
                         citation: "§387 NET-30 PAYOR · NET-30 12D",
                         title: "Settlement detail",
                         subhead: "SHIP-001-EUSORONE · LD-…7E · NET-30 12D",
                         pillCopy: "Catalyst earns from shipper · same companyId both sides · clean payor records",
                         rowId: "INV-260427-A38FB12C7E",
                         statusBadge: "NET-30 · 12D OUTSTANDING", statusColor: .green, grade: "A")
        case .onboarding:
            return .init(eyebrow: "CATALYST · CUSTOMER · STEP DETAIL",
                         citation: "§387 · COMPLETE",
                         title: "Step detail",
                         subhead: "SHIP-001-EUSORONE · §387 · 6/6 closed",
                         pillCopy: "Catalyst onboards shipper · same companyId · all 6 pillars closed 2024-08-04",
                         rowId: "STEP-260427-MSA-SHIP001",
                         statusBadge: "TERMINAL · 6/6", statusColor: .green, grade: "A")
        case .compliance:
            return .init(eyebrow: "CATALYST · CUSTOMER · COMPLIANCE ROW",
                         citation: "§387 §388 · CLEAN",
                         title: "Compliance row",
                         subhead: "SHIP-001-EUSORONE · §388 · BROKER AUTH",
                         pillCopy: "Catalyst monitors payor · same companyId · clean §387 (cargo liability) §388 (broker auth)",
                         rowId: "COMP-260427-AUTH-SHIP001",
                         statusBadge: "CLEAN · 0 DISPUTES", statusColor: .green, grade: "A")
        case .quarter:
            return .init(eyebrow: "CATALYST · CUSTOMER · QUARTER DETAIL",
                         citation: "Q1-2026 · CLOSED",
                         title: "Quarter detail",
                         subhead: "SHIP-001-EUSORONE · Q1-2026 · CLOSED",
                         pillCopy: "Catalyst archives Q1 payor rollup · same companyId both sides · clean §6041 1099-NEC closed quarter",
                         rowId: "PERF-260331-Q1ROLL-EUSORONE",
                         statusBadge: "CLOSED · QC LOGGED", statusColor: .green, grade: "A")
        }
    }
}

private struct CatalystShipperBShell<Content: View>: View {
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

private struct CatalystShipperBBody: View {
    let kind: CatalystShipperBKind

    @Environment(\.palette) private var palette
    @State private var resp: CSBResp?

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

    private func header(_ c: CSBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func citationPill(_ c: CSBConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · \(c.citation)").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func rowCard(_ c: CSBConfig) -> some View {
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
                    .overlay(Text("DU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diego Usoro · founder · Eusorone Technologies").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("SHIP-001-EUSORONE · companyId 1 · EIN 87-3104952 · MATRIX-50").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CSBConfig) -> some View {
        let grade = resp?.grade ?? "A"
        let m = resp?.metrics
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scoreAxis:
                return [
                    ("GRADE",    grade,                                              "composite axis · §9.5",  .green),
                    ("TENDER",   String(format: "%.1f%%", m?.tenderAcceptance ?? 88), "acceptance",          .green),
                    ("LOADS",    "\(m?.totalLoads ?? 9)",                              "90d aggregate",       .blue),
                    ("STATE",    "LIVE",                                                c.statusBadge,        .green),
                ]
            case .profileTier:
                return [
                    ("TIER",     "GOLD",                                                  "Eusorone · §13.5",   .green),
                    ("EIN",      "87-3104952",                                              "verified",        .blue),
                    ("STATE",    "LIVE",                                                    c.statusBadge,     .green),
                    ("EFFECT",   "+0.06",                                                    "pillar boost",   .green),
                ]
            case .document:
                return [
                    ("DOC",      "COI",                                                      "§387.7 · auto+general", .green),
                    ("STATE",    "ON FILE",                                                   c.statusBadge,    .green),
                    ("RUNWAY",   "187d",                                                        "to expiry",   .green),
                    ("OWNER",    "Eusorone",                                                    "on file",     .blue),
                ]
            case .analytic:
                return [
                    ("DSO",      "5.8d",                                                         "Eusorone floor",  .green),
                    ("TENDER",   String(format: "%.1f%%", m?.tenderAcceptance ?? 88),             "acceptance",     .green),
                    ("STATE",    "LIVE",                                                          c.statusBadge,    .green),
                    ("RPM",      "$5.12",                                                          "lane average",  .blue),
                ]
            case .settlement:
                return [
                    ("INVOICE",  "$1,805",                                                          "this allocation",  .green),
                    ("CHAIN",    "LD-...7E",                                                         "billed",         .blue),
                    ("STATE",    "NET-30",                                                            "12d outstanding", .green),
                    ("BOOK",     "§387",                                                              "payor clean",   .blue),
                ]
            case .onboarding:
                return [
                    ("STEPS",    "6/6",                                                                "MSA · COI · etc",    .green),
                    ("STATE",    "TERMINAL",                                                            c.statusBadge,       .green),
                    ("CLOSED",   "2024-08-04",                                                           "anniversary",     .blue),
                    ("OWNER",    "Eusorone",                                                              "all closed",     .green),
                ]
            case .compliance:
                return [
                    ("AUTH",     "BROKER",                                                                 "§388 · MC-306",  .green),
                    ("STATE",    "CLEAN",                                                                   c.statusBadge,   .green),
                    ("DISPUTES", "0",                                                                        "YTD",           .green),
                    ("CARGO",    "$100K",                                                                     "§387 minimum",  .green),
                ]
            case .quarter:
                return [
                    ("Q1",       "CLOSED",                                                                    "2026-03-31",     .green),
                    ("INVOICES", "\(m?.totalLoads ?? 9)",                                                     "$14,820 gross", .green),
                    ("1099-NEC", "READY",                                                                      "§6041 closed",  .blue),
                    ("STATE",    "QC LOGGED",                                                                   c.statusBadge,  .green),
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
            case .scoreAxis:   return "Composite axis A. Pinned to §9.5 shipper books — refresh weekly with the next QC cycle."
            case .profileTier: return "Gold tier (§13.5) holds +0.06 pillar boost. Reconfirm criteria on Q2 baseline."
            case .document:    return "COI (§387.7) on file with 187d runway. Set 60-day reminder before anniversary."
            case .analytic:    return "DSO 5.8d, tender 88%. Best-in-class payor — replicate the playbook on dormant accounts."
            case .settlement:  return "Invoice A38FB12C7E at $1,805, NET-30, 12d outstanding. Auto-collect at maturity."
            case .onboarding:  return "All 6 steps closed (MSA / W-9 / COI / terms / rate-card / first PO). Lock for Q2."
            case .compliance:  return "§387 §388 clean. Renew COI 30 days before 2026-08-04 anniversary."
            case .quarter:     return "Q1 closed 2026-03-31. 1099-NEC ready for §6041 export end-of-quarter."
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
        do { resp = try await EusoTripAPI.shared.query("shipperScorecard.getScorecard", input: In(shipperId: 0, periodDays: 90)) } catch { /* */ }
    }
}

// MARK: - Screens (CV340B-CV347B)

struct CatalystShipperScoreAxisScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystShipperBShell(theme: theme) { CatalystShipperBBody(kind: .scoreAxis) } }
}
struct CatalystShipperProfileTierScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystShipperBShell(theme: theme) { CatalystShipperBBody(kind: .profileTier) } }
}
struct CatalystShipperDocumentDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystShipperBShell(theme: theme) { CatalystShipperBBody(kind: .document) } }
}
struct CatalystShipperAnalyticDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystShipperBShell(theme: theme) { CatalystShipperBBody(kind: .analytic) } }
}
struct CatalystShipperSettlementDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystShipperBShell(theme: theme) { CatalystShipperBBody(kind: .settlement) } }
}
struct CatalystShipperStepDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystShipperBShell(theme: theme) { CatalystShipperBBody(kind: .onboarding) } }
}
struct CatalystShipperComplianceRowScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystShipperBShell(theme: theme) { CatalystShipperBBody(kind: .compliance) } }
}
struct CatalystShipperQuarterDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { CatalystShipperBShell(theme: theme) { CatalystShipperBBody(kind: .quarter) } }
}

// MARK: - Previews

#Preview("340B Axis · Dark")     { CatalystShipperScoreAxisScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("341B Tier · Light")    { CatalystShipperProfileTierScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("342B Doc · Dark")      { CatalystShipperDocumentDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("343B Analytic · Light"){ CatalystShipperAnalyticDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("344B Settle · Dark")   { CatalystShipperSettlementDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("345B Step · Light")    { CatalystShipperStepDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("346B Comp · Dark")     { CatalystShipperComplianceRowScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("347B Q1 · Light")      { CatalystShipperQuarterDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
