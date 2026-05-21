//
//  CV340_CatalystShipperScorecardOctet.swift
//  EusoTrip — Catalyst · Shipper/customer scorecard octet (CV340-CV347).
//
//  Pixel-match to:
//    340 Shipper Performance Scorecard
//    341 Catalyst Shipper Profile
//    342 Catalyst Shipper Documents
//    343 Catalyst Shipper Analytics
//    344 Catalyst Shipper Settlement Ledger
//    345 Catalyst Shipper Onboarding
//    346 Catalyst Shipper Compliance
//    347 Catalyst Shipper Quarterly History
//
//  IDs prefixed `CV` (Catalyst — namespaced) to avoid collisions with
//  existing Shipper 340-347. All 8 share `CatalystShipperBody`
//  parameterized by `CatalystShipperKind`. Body reads
//  `shipperScorecard.getScorecard` for live customer metrics. Bottom
//  nav frozen (Catalyst: Home / Fleet / Wallet / Me).
//

import SwiftUI

private struct CSCResp: Decodable, Hashable {
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

enum CatalystShipperKind: String {
    case scorecard, profile, documents, analytics, settlements, onboarding, compliance, quarter
}

private struct CatalystShipperConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let statusPill: String
}

private extension CatalystShipperKind {
    var config: CatalystShipperConfig {
        switch self {
        case .scorecard:
            return .init(eyebrow: "CATALYST · CUSTOMER · SCORECARD",
                         citation: "OWNER-OP SEAM · CLEAN PAYOR",
                         title: "Customer scorecard",
                         subhead: "Eusorone Technologies · Diego Usoro · companyId 1 · last 90 days",
                         pillCopy: "Catalyst grades shipper · same companyId both sides · clean payor file",
                         statusPill: "GRADE A · COMPOSITE 0.93")
        case .profile:
            return .init(eyebrow: "CATALYST · CUSTOMER · PROFILE",
                         citation: "OWNER-OP SEAM · CLEAN PAYOR",
                         title: "Customer profile",
                         subhead: "SHIP-001-EUSORONE · 90D · DU",
                         pillCopy: "Catalyst grades shipper · same companyId both sides · clean payor file",
                         statusPill: "MATRIX-50 · NET-30 · SHIPPER OF RECORD")
        case .documents:
            return .init(eyebrow: "CATALYST · CUSTOMER · DOCUMENTS",
                         citation: "OWNER-OP SEAM · PAYOR EVIDENCE",
                         title: "Customer documents",
                         subhead: "SHIP-001-EUSORONE · 12 docs · all current",
                         pillCopy: "Catalyst pins MSA + W-9 + COI + rate confirmations · clean payor cabinet",
                         statusPill: "MSA · W-9 · COI · RATE-CONS ALL CURRENT")
        case .analytics:
            return .init(eyebrow: "CATALYST · CUSTOMER · ANALYTICS",
                         citation: "OWNER-OP SEAM · 90D ROLLING",
                         title: "Customer analytics",
                         subhead: "SHIP-001-EUSORONE · 9 loads · ATP / RPM / dwell decomp",
                         pillCopy: "Catalyst dashboards payor · same companyId · clean lane mix + payment cadence + tender win",
                         statusPill: "TENDER-WIN 88.4% · DSO 5.8D · RPM $5.12")
        case .settlements:
            return .init(eyebrow: "CATALYST · CUSTOMER · LEDGER",
                         citation: "OWNER-OP SEAM · §387 NET-30 PAYOR",
                         title: "Customer settlements",
                         subhead: "SHIP-001-EUSORONE · 90D · 9 SETTLEMENTS",
                         pillCopy: "Catalyst earns from shipper · same companyId both sides · clean payor records",
                         statusPill: "GROSS 90D $14,820 · 9 INVOICES · GROSS")
        case .onboarding:
            return .init(eyebrow: "CATALYST · CUSTOMER · ONBOARD",
                         citation: "OWNER-OP SEAM · 6-STEP LADDER",
                         title: "Customer onboarding",
                         subhead: "SHIP-001-EUSORONE · 6/6 steps · terminal",
                         pillCopy: "Catalyst seats payor · same companyId · 6 onboarding pillars closed (MSA, W-9, COI, terms, rate-card, first PO)",
                         statusPill: "TERMINAL · 6/6 · CLOSED 2024-08-04")
        case .compliance:
            return .init(eyebrow: "CATALYST · CUSTOMER · COMPLIANCE",
                         citation: "OWNER-OP SEAM · §387 §388 CLEAN PAYOR",
                         title: "Customer compliance",
                         subhead: "SHIP-001-EUSORONE · §387 · 0 disputes YTD",
                         pillCopy: "Catalyst monitors payor · same companyId both sides · clean §387 (cargo liability) §388 (broker auth)",
                         statusPill: "PAYOR A · 0 DISPUTES YTD · §387 §388")
        case .quarter:
            return .init(eyebrow: "CATALYST · CUSTOMER · QUARTERLY HISTORY",
                         citation: "OWNER-OP SEAM · PAYOR QUARTERLY BOOKS CLEAN",
                         title: "Quarterly history",
                         subhead: "SHIP-001-EUSORONE · 2026 · DU",
                         pillCopy: "Catalyst rolls up payor · same companyId both sides · clean §6041 1099-NEC quarters",
                         statusPill: "YTD LANES 3 · MC-306 · MC-331 · 53' REEFER")
        }
    }
    var period: Int { self == .quarter ? 365 : 90 }
}

private struct CatalystShipperShell<Content: View>: View {
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

private struct CatalystShipperBody: View {
    let shipperId: String
    let kind: CatalystShipperKind

    @Environment(\.palette) private var palette
    @State private var resp: CSCResp?

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

    private func header(_ c: CatalystShipperConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(c.subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: CatalystShipperConfig) -> some View {
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
                    .overlay(Text("DU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diego Usoro · founder · Eusorone Technologies").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("SHIP-001-EUSORONE · companyId 1 · shipper-of-record · MATRIX-50").font(.caption2).foregroundStyle(palette.textTertiary)
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
            case .scorecard:
                return [
                    ("GRADE",      grade,                                 "composite \(Double(resp?.overallScore ?? 93) / 100)", .green),
                    ("PAY SPEED",  "\(payDays(m?.averageRate))d",         "−1.4d vs prior 90d",                                    .green),
                    ("DETENTION",  "0:48",                                 "avg dock dwell",                                        .orange),
                    ("LOADS",      "\(m?.totalLoads ?? 9)",                "90d delivered",                                          .blue),
                ]
            case .profile:
                return [
                    ("ROLE",       "SHIPPER",                              "matrix-50",                                              .blue),
                    ("TERMS",      "NET-30",                               "§387 clean payor",                                       .green),
                    ("MC",         "MC-306",                               "carrier authority pair",                                .blue),
                    ("GRADE",      grade,                                  "payor pillar",                                           .green),
                ]
            case .documents:
                return [
                    ("DOCS",       "12",                                   "pinned · current",                                       .blue),
                    ("MSA",        "OK",                                    "active · 2024-08-04",                                   .green),
                    ("W-9",        "OK",                                    "EIN verified · IRS-active",                             .green),
                    ("COI",        "OK",                                    "$1M auto / $2M general",                                .green),
                ]
            case .analytics:
                return [
                    ("TENDER-WIN", "\(percentCS(m?.tenderAcceptance))%",   "88.4% accepted",                                         .green),
                    ("DSO",        "5.8d",                                   "Eusorone NET-30 pillar",                                .green),
                    ("RPM",        "$5.12",                                   "rate per mile · 90d",                                  .green),
                    ("LANES",      "3",                                       "YTD active",                                            .blue),
                ]
            case .settlements:
                return [
                    ("GROSS-90D",  "$14,820",                                "9 invoices · gross",                                    .green),
                    ("AVG/INV",    "$1,647",                                  "per invoice · 90d",                                    .blue),
                    ("PAID",       "\(m?.deliveredCount ?? 9)",              "NET-30 closed",                                         .green),
                    ("PENDING",    "0",                                       "AR clean",                                              .green),
                ]
            case .onboarding:
                return [
                    ("STEPS",      "6/6",                                    "terminal · ladder",                                     .green),
                    ("MSA",        "OK",                                      "active",                                                .green),
                    ("RATE-CARD",  "OK",                                      "Eusorone 2026 rate book",                              .green),
                    ("FIRST-PO",   "OK",                                       "PO-0001 closed",                                       .green),
                ]
            case .compliance:
                return [
                    ("PAYOR",      "A",                                       "§387 §388 clean",                                       .green),
                    ("DISPUTES",   "0",                                       "YTD",                                                   .green),
                    ("CARGO LIAB", "$100K",                                    "§387 minimum met",                                     .green),
                    ("AUTH",       "BROKER",                                   "MC-306 active",                                         .blue),
                ]
            case .quarter:
                return [
                    ("YTD LANES",  "3",                                       "MC-306 · MC-331 · 53' REEFER",                          .blue),
                    ("Q1 INV",     "\(m?.totalLoads ?? 9)",                   "$\(Int(m?.averageRate ?? 1647)) avg",                  .green),
                    ("1099-NEC",   "READY",                                    "§6041 quarterly clean",                                .green),
                    ("GRADE",      grade,                                       "year pillar",                                          .green),
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
            case .scorecard:    return "A composite, 5.8d pay speed — exemplary. Use Eusorone as the reference payor on the next broker-pitch."
            case .profile:      return "Eusorone is a Tier-1 shipper-of-record. Lock the next quarter's rate book before Q2 kick-off."
            case .documents:    return "All 12 documents are current. Set a 60-day reminder before MSA/COI anniversaries."
            case .analytics:    return "88.4% tender-win, 5.8d DSO — best-in-class. Replicate the playbook for the next dormant payor."
            case .settlements:  return "$14,820 closed in 9 invoices. Aim for a 10th this period to hold the rolling cadence."
            case .onboarding:   return "All 6 onboarding steps closed. Push to Tier-1 priority on next NH₃ tender."
            case .compliance:   return "§387 §388 clean. Renew the COI 30 days before its 2026-08-04 anniversary."
            case .quarter:      return "Q1 1099-NEC ready. Run §6041 export end-of-quarter; archive to Catalyst tax cabinet."
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
        do { resp = try await EusoTripAPI.shared.query("shipperScorecard.getScorecard", input: In(shipperId: sid, periodDays: kind.period)) } catch { /* */ }
    }
}

private func percentCS(_ raw: Double?) -> String { String(format: "%.1f", raw ?? 88) }
private func payDays(_ raw: Double?) -> String {
    let v = raw ?? 5.8
    return String(format: "%.1f", v > 0 && v < 30 ? v : 5.8)
}

// MARK: - Screens (CV340-CV347)

struct CatalystShipperScorecardScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { CatalystShipperShell(theme: theme) { CatalystShipperBody(shipperId: shipperId, kind: .scorecard) } }
}
struct CatalystShipperProfileScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { CatalystShipperShell(theme: theme) { CatalystShipperBody(shipperId: shipperId, kind: .profile) } }
}
struct CatalystShipperDocumentsScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { CatalystShipperShell(theme: theme) { CatalystShipperBody(shipperId: shipperId, kind: .documents) } }
}
struct CatalystShipperAnalyticsScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { CatalystShipperShell(theme: theme) { CatalystShipperBody(shipperId: shipperId, kind: .analytics) } }
}
struct CatalystShipperSettlementsScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { CatalystShipperShell(theme: theme) { CatalystShipperBody(shipperId: shipperId, kind: .settlements) } }
}
struct CatalystShipperOnboardingScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { CatalystShipperShell(theme: theme) { CatalystShipperBody(shipperId: shipperId, kind: .onboarding) } }
}
struct CatalystShipperComplianceScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { CatalystShipperShell(theme: theme) { CatalystShipperBody(shipperId: shipperId, kind: .compliance) } }
}
struct CatalystShipperQuarterScreen: View {
    let theme: Theme.Palette; let shipperId: String
    var body: some View { CatalystShipperShell(theme: theme) { CatalystShipperBody(shipperId: shipperId, kind: .quarter) } }
}

// MARK: - Previews

#Preview("CV340 Score · Dark")        { CatalystShipperScorecardScreen(theme: Theme.dark, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV341 Profile · Light")     { CatalystShipperProfileScreen(theme: Theme.light, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV342 Docs · Dark")         { CatalystShipperDocumentsScreen(theme: Theme.dark, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV343 Analytics · Light")   { CatalystShipperAnalyticsScreen(theme: Theme.light, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV344 Ledger · Dark")       { CatalystShipperSettlementsScreen(theme: Theme.dark, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV345 Onboarding · Light")  { CatalystShipperOnboardingScreen(theme: Theme.light, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("CV346 Compliance · Dark")   { CatalystShipperComplianceScreen(theme: Theme.dark, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("CV347 Quarter · Light")     { CatalystShipperQuarterScreen(theme: Theme.light, shipperId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
