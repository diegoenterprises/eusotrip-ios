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
//  ZERO-FABRICATION BINDING (2026-06-06):
//  Every KPI is bound to the typed `shipperScorecard.getScorecard`
//  response (overallScore / grade / metrics.{tenderAcceptance,
//  completionRate, cancellationRate, averageRate, volumeConsistency,
//  totalLoads, deliveredCount, cancelledCount}). The proc returns NO
//  per-doc compliance (MSA/W-9/COI), NO per-invoice settlement
//  line-items, NO DSO-in-days / RPM / detention, NO onboarding-step
//  ladder, NO 1099/quarterly rollup, NO carrier authority (MC) and NO
//  shipper/company NAME — only the numeric shipperId echo. Those rows
//  render an honest "—" placeholder; identity shows the real
//  `shipperId` from the proc, never a hardcoded persona. No `??
//  <invented>` fallbacks remain — absent fields collapse to "—".
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
                         subhead: "shipperScorecard.getScorecard · last 90 days",
                         pillCopy: "Catalyst grades the shipper-payor on tender acceptance, completion, cancellation, volume consistency and average rate.",
                         statusPill: "GRADE + COMPOSITE · LIVE")
        case .profile:
            return .init(eyebrow: "CATALYST · CUSTOMER · PROFILE",
                         citation: "OWNER-OP SEAM · CLEAN PAYOR",
                         title: "Customer profile",
                         subhead: "shipperScorecard.getScorecard · 90 days",
                         pillCopy: "Catalyst grades the shipper-payor on tender acceptance, completion, cancellation, volume consistency and average rate.",
                         statusPill: "PAYOR GRADE · LIVE")
        case .documents:
            return .init(eyebrow: "CATALYST · CUSTOMER · DOCUMENTS",
                         citation: "OWNER-OP SEAM · PAYOR EVIDENCE",
                         title: "Customer documents",
                         subhead: "per-document vault not in scorecard proc",
                         pillCopy: "Catalyst pins MSA + W-9 + COI + rate confirmations in the payor document cabinet. Per-document status is not returned by the scorecard proc.",
                         statusPill: "DOCUMENT VAULT · NOT IN SCORECARD PROC")
        case .analytics:
            return .init(eyebrow: "CATALYST · CUSTOMER · ANALYTICS",
                         citation: "OWNER-OP SEAM · 90D ROLLING",
                         title: "Customer analytics",
                         subhead: "shipperScorecard.getScorecard · 90 days",
                         pillCopy: "Catalyst dashboards the payor on tender acceptance, completion and average rate. DSO-in-days and rate-per-mile are not returned by the scorecard proc.",
                         statusPill: "TENDER-ACCEPT · AVG RATE · LIVE")
        case .settlements:
            return .init(eyebrow: "CATALYST · CUSTOMER · LEDGER",
                         citation: "OWNER-OP SEAM · §387 NET-30 PAYOR",
                         title: "Customer settlements",
                         subhead: "per-invoice ledger not in scorecard proc",
                         pillCopy: "Catalyst earns from the shipper-payor. Per-invoice settlement line-items are not returned by the scorecard proc — only delivered-load counts are live.",
                         statusPill: "DELIVERED COUNT · LIVE")
        case .onboarding:
            return .init(eyebrow: "CATALYST · CUSTOMER · ONBOARD",
                         citation: "OWNER-OP SEAM · 6-STEP LADDER",
                         title: "Customer onboarding",
                         subhead: "onboarding ladder not in scorecard proc",
                         pillCopy: "Catalyst seats the payor across MSA, W-9, COI, terms, rate-card and first PO. The onboarding-step ladder is not returned by the scorecard proc.",
                         statusPill: "ONBOARDING LADDER · NOT IN SCORECARD PROC")
        case .compliance:
            return .init(eyebrow: "CATALYST · CUSTOMER · COMPLIANCE",
                         citation: "OWNER-OP SEAM · §387 §388 CLEAN PAYOR",
                         title: "Customer compliance",
                         subhead: "shipperScorecard.getScorecard · 90 days",
                         pillCopy: "Catalyst monitors the payor on cancellation rate and dispute exposure. §387 §388 document checks are not returned by the scorecard proc.",
                         statusPill: "CANCELLATION RATE · LIVE")
        case .quarter:
            return .init(eyebrow: "CATALYST · CUSTOMER · QUARTERLY HISTORY",
                         citation: "OWNER-OP SEAM · PAYOR QUARTERLY BOOKS",
                         title: "Quarterly history",
                         subhead: "365-day rolling · scorecard proc",
                         pillCopy: "Catalyst rolls up the payor across the year. Per-quarter and §6041 1099-NEC rollups are not returned by the scorecard proc — only 365-day aggregates are live.",
                         statusPill: "365-DAY AGGREGATE · LIVE")
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

    // Identity comes ONLY from the real proc echo (`shipperId`). The
    // scorecard proc returns no shipper/company NAME, so the name line
    // renders the real id and the secondary line stays an honest "—".
    private var identityRow: some View {
        let id = resp?.shipperId
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "shippingbox.fill").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(id.map { "Shipper #\($0)" } ?? "Shipper · —")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("shipper-of-record · name not in scorecard proc · —")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let m = resp?.metrics
        let grade = resp?.grade ?? "—"
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scorecard:
                return [
                    ("GRADE",      grade,                        compositeLine(resp?.overallScore),      .green),
                    ("TENDER-ACC", pct(m?.tenderAcceptance),     "accepted · 90d",                        .green),
                    ("COMPLETION", pct(m?.completionRate),       "delivered / total · 90d",               .blue),
                    ("LOADS",      intStr(m?.totalLoads),        "90d total",                             .blue),
                ]
            case .profile:
                return [
                    ("ROLE",       "SHIPPER",                    "shipper-of-record",                     .blue),
                    ("GRADE",      grade,                        "payor pillar",                          .green),
                    ("DELIVERED",  intStr(m?.deliveredCount),    "completed · 90d",                       .green),
                    ("CANCELLED",  intStr(m?.cancelledCount),    "cancelled · 90d",                       .red),
                ]
            case .documents:
                // Per-document compliance (MSA / W-9 / COI / rate-cons) is a
                // backend gap — the scorecard proc returns none. Honest "—".
                return [
                    ("MSA",        "—",                          "not in scorecard proc",                 .gray),
                    ("W-9",        "—",                          "not in scorecard proc",                 .gray),
                    ("COI",        "—",                          "not in scorecard proc",                 .gray),
                    ("RATE-CONS",  "—",                          "not in scorecard proc",                 .gray),
                ]
            case .analytics:
                return [
                    ("TENDER-ACC", pct(m?.tenderAcceptance),     "accepted · 90d",                        .green),
                    ("AVG RATE",   moneyStr(m?.averageRate),     "avg delivered-load rate · 90d",         .green),
                    ("VOL-CONS",   pct(m?.volumeConsistency),    "month-over-month · 90d",                .blue),
                    ("DSO / RPM",  "—",                          "not in scorecard proc",                 .gray),
                ]
            case .settlements:
                // Per-invoice settlement line-items + gross are a backend gap.
                // Only delivered-load count is live; gross / per-invoice "—".
                return [
                    ("DELIVERED",  intStr(m?.deliveredCount),    "completed loads · 90d",                 .green),
                    ("AVG RATE",   moneyStr(m?.averageRate),     "avg delivered-load rate · 90d",         .blue),
                    ("GROSS 90D",  "—",                          "per-invoice ledger not in proc",        .gray),
                    ("AR PENDING", "—",                          "per-invoice ledger not in proc",        .gray),
                ]
            case .onboarding:
                // 6-step onboarding ladder is a backend gap — proc returns none.
                return [
                    ("STEPS",      "—",                          "ladder not in scorecard proc",          .gray),
                    ("MSA",        "—",                          "not in scorecard proc",                 .gray),
                    ("RATE-CARD",  "—",                          "not in scorecard proc",                 .gray),
                    ("FIRST-PO",   "—",                          "not in scorecard proc",                 .gray),
                ]
            case .compliance:
                return [
                    ("CANCEL RT",  pct(m?.cancellationRate),     "cancelled / total · 90d",               .orange),
                    ("COMPLETION", pct(m?.completionRate),       "delivered / total · 90d",               .green),
                    ("PAYOR GRD",  grade,                        "composite pillar",                      .green),
                    ("§387 §388",  "—",                          "document checks not in proc",           .gray),
                ]
            case .quarter:
                // Per-quarter + 1099-NEC rollups are a backend gap. The proc
                // returns 365-day aggregates only; per-quarter rows are "—".
                return [
                    ("LOADS 365D", intStr(m?.totalLoads),        "365-day total",                         .blue),
                    ("DELIVERED",  intStr(m?.deliveredCount),    "365-day completed",                     .green),
                    ("AVG RATE",   moneyStr(m?.averageRate),     "avg delivered-load rate · 365d",        .blue),
                    ("1099-NEC",   "—",                          "per-quarter rollup not in proc",        .gray),
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
            case .scorecard:    return "Composite grade and tender-acceptance are live from the scorecard proc. Use the grade to set tender priority and payment terms for this payor."
            case .profile:      return "Delivered and cancelled counts are live. Shipper/company name is not returned by the scorecard proc — resolve via the user/company directory when needed."
            case .documents:    return "Per-document status (MSA / W-9 / COI / rate-confirmations) is not exposed by the scorecard proc. Pull it from the compliance document vault."
            case .analytics:    return "Tender-acceptance, average rate and volume-consistency are live. DSO-in-days and rate-per-mile are not returned by this proc."
            case .settlements:  return "Delivered-load count and average rate are live. Per-invoice gross and AR are not returned by the scorecard proc — read the settlement ledger."
            case .onboarding:   return "The 6-step onboarding ladder is not returned by the scorecard proc. Drive it from the onboarding workflow service."
            case .compliance:   return "Cancellation and completion rates are live. §387 §388 document checks and dispute history are not returned by this proc."
            case .quarter:      return "365-day load, delivered and average-rate aggregates are live. Per-quarter and 1099-NEC rollups are not returned by the scorecard proc."
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

// MARK: - Honest formatters (no invented fallbacks — absent -> "—")

/// Percentage from a live Double field, e.g. `tenderAcceptance` already
/// in 0-100 from the proc. Absent field renders an honest "—".
private func pct(_ raw: Double?) -> String {
    guard let raw else { return "—" }
    return String(format: "%.1f%%", raw)
}

/// Integer count from a live Int field. Absent renders "—".
private func intStr(_ raw: Int?) -> String {
    guard let raw else { return "—" }
    return "\(raw)"
}

/// Money from the proc's `averageRate` (rounded dollars). Absent -> "—".
private func moneyStr(_ raw: Double?) -> String {
    guard let raw else { return "—" }
    return "$" + String(format: "%.0f", raw)
}

/// Composite caption from the live `overallScore` (0-100 integer the
/// proc computes). Absent renders an honest "composite —".
private func compositeLine(_ score: Int?) -> String {
    guard let score else { return "composite —" }
    return "composite \(String(format: "%.2f", Double(score) / 100))"
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
