//
//  CV340B_CatalystShipperBVariantOctet.swift
//  EusoTrip — Catalyst · Shipper B-variant deep-drill octet (340B-347B).
//
//  Pixel-match to:
//    340B Catalyst Shipper Scorecard Axis Detail   (§9.5 · COMPOSITE)
//    341B Catalyst Shipper Profile Tier Detail
//    342B Catalyst Shipper Document Detail
//    343B Catalyst Shipper Analytic Detail
//    344B Catalyst Shipper Settlement Detail
//    345B Catalyst Shipper Onboarding Step Detail
//    346B Catalyst Shipper Compliance Row Detail
//    347B Catalyst Shipper Quarter Detail
//
//  Closes the Catalyst B-variant set (24/24). Body reads the typed
//  `shipperScorecard.getScorecard` proc (frontend/server/routers/
//  shipperScorecard.ts:16) for the live composite + metrics, and the
//  authenticated session (`EusoTripSession.user` → `AuthUser`) for the
//  real shipper identity. Bottom nav frozen.
//
//  ZERO FABRICATION: the only live fields this proc exposes are
//  overallScore / grade and metrics{tenderAcceptance, completionRate,
//  cancellationRate, averageRate, volumeConsistency, totalLoads,
//  deliveredCount, cancelledCount} + volumeByMonth. There is NO tier,
//  EIN, document cabinet, DSO, RPM, per-invoice settlement line-item,
//  onboarding-step ledger, compliance row, or quarter rollup behind this
//  proc — every such sub-field renders an honest "—" (or, for the
//  per-invoice settlement that is a confirmed backend gap, an honest
//  EusoEmptyState). Identity comes from the session, never a persona.
//

import SwiftUI

private struct CSBResp: Decodable, Hashable {
    let shipperId: Int?
    let periodDays: Int?
    let overallScore: Int?
    let grade: String?
    let metrics: M?
    struct M: Decodable, Hashable {
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

enum CatalystShipperBKind: String {
    case scoreAxis, profileTier, document, analytic, settlement, onboarding, compliance, quarter
}

private struct CSBConfig {
    let eyebrow: String
    let citation: String
    let title: String
    let subhead: String
    let pillCopy: String
    let rowIdPrefix: String
    let statusBadge: String
    let statusColor: Color
}

private extension CatalystShipperBKind {
    var config: CSBConfig {
        switch self {
        case .scoreAxis:
            return .init(eyebrow: "CATALYST · CUSTOMER · SCORECARD AXIS",
                         citation: "§9.5 · LIVE",
                         title: "Axis detail",
                         subhead: "Catalyst · customer composite · §9.5 · LIVE",
                         pillCopy: "Catalyst rates shipper · same company both sides · clean §9.5 shipper books",
                         rowIdPrefix: "SCORE",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green)
        case .profileTier:
            return .init(eyebrow: "CATALYST · SHIPPER · TIER",
                         citation: "§13.5 · LIVE",
                         title: "Tier detail",
                         subhead: "Catalyst · customer tier · §13.5 · LIVE",
                         pillCopy: "Catalyst rates shipper · same company both sides · clean §13.5 tier criteria",
                         rowIdPrefix: "TIER",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green)
        case .document:
            return .init(eyebrow: "CATALYST · CUSTOMER · DOCUMENT",
                         citation: "§387.7",
                         title: "Document detail",
                         subhead: "Catalyst · customer document cabinet · §387.7",
                         pillCopy: "Catalyst archives shipper docs · same company both sides · clean §387.7 COI cabinet",
                         rowIdPrefix: "DOC",
                         statusBadge: "DOCUMENT CABINET", statusColor: .secondary)
        case .analytic:
            return .init(eyebrow: "CATALYST · CUSTOMER · ANALYTIC",
                         citation: "§9.5 · LIVE",
                         title: "Analytic detail",
                         subhead: "Catalyst · payor KPIs · §9.5 · LIVE",
                         pillCopy: "Catalyst tracks payor KPIs · same company · clean tender-win + completion + lane mix",
                         rowIdPrefix: "PERF",
                         statusBadge: "PUBLISHED · LIVE", statusColor: .green)
        case .settlement:
            return .init(eyebrow: "CATALYST · CUSTOMER · SETTLEMENT",
                         citation: "§387 NET-30 PAYOR",
                         title: "Settlement detail",
                         subhead: "Catalyst · payor settlement · §387",
                         pillCopy: "Catalyst earns from shipper · same company both sides · clean payor records",
                         rowIdPrefix: "INV",
                         statusBadge: "PAYOR SETTLEMENT", statusColor: .secondary)
        case .onboarding:
            return .init(eyebrow: "CATALYST · CUSTOMER · STEP DETAIL",
                         citation: "§387",
                         title: "Step detail",
                         subhead: "Catalyst · onboarding ladder · §387",
                         pillCopy: "Catalyst onboards shipper · same company · onboarding ladder",
                         rowIdPrefix: "STEP",
                         statusBadge: "ONBOARDING LADDER", statusColor: .secondary)
        case .compliance:
            return .init(eyebrow: "CATALYST · CUSTOMER · COMPLIANCE ROW",
                         citation: "§387 §388",
                         title: "Compliance row",
                         subhead: "Catalyst · payor compliance · §387 §388",
                         pillCopy: "Catalyst monitors payor · same company · §387 (cargo liability) §388 (broker auth)",
                         rowIdPrefix: "COMP",
                         statusBadge: "COMPLIANCE MONITOR", statusColor: .secondary)
        case .quarter:
            return .init(eyebrow: "CATALYST · CUSTOMER · QUARTER DETAIL",
                         citation: "QUARTERLY",
                         title: "Quarter detail",
                         subhead: "Catalyst · payor quarterly rollup",
                         pillCopy: "Catalyst archives payor quarterly rollup · same company both sides · §6041 1099-NEC",
                         rowIdPrefix: "PERF",
                         statusBadge: "QUARTERLY ROLLUP", statusColor: .secondary)
        }
    }
}

private struct CatalystShipperBShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .drivers),
                trailing: CarrierNavRoute.trailing(current: .drivers),
                orbState: .idle
            )
        }
    }
}

private struct CatalystShipperBBody: View {
    let kind: CatalystShipperBKind

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var resp: CSBResp?

    // Honest placeholder for any field with no live source behind getScorecard.
    private let none = "—"

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                citationPill(c)
                rowCard(c)
                identityRow
                kpiGrid(c)
                if kind == .settlement { settlementGapCard }
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private func header(_ c: CSBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
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

    // The grade glyph is the live composite grade from getScorecard, falling
    // back to the honest placeholder before the proc returns.
    private func rowCard(_ c: CSBConfig) -> some View {
        let grade = resp?.grade ?? none
        // Honest row id: the prefix + the live shipperId echoed by the proc.
        // No invented hash/date suffix (e.g. the old "260427-COMPOSITE-EUSORONE").
        let rowId: String = {
            if let sid = resp?.shipperId { return "\(c.rowIdPrefix)-\(sid)" }
            return "\(c.rowIdPrefix)-\(none)"
        }()
        return LifecycleCard {
            HStack(spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(grade).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowId).font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(c.statusBadge).font(.caption2).foregroundStyle(c.statusColor)
                }
                Spacer()
            }
        }
    }

    // Identity from the authenticated session — never a hardcoded persona.
    private var identityRow: some View {
        let user = session.user
        let name = (user?.name?.isEmpty == false) ? user!.name! : none
        let initials: String = {
            guard let n = user?.name, !n.isEmpty else { return "—" }
            let parts = n.split(separator: " ")
            let chars = parts.prefix(2).compactMap { $0.first }
            return chars.isEmpty ? "—" : String(chars).uppercased()
        }()
        let companyId = (user?.companyId?.isEmpty == false) ? user!.companyId! : none
        let role = (user?.role.isEmpty == false) ? user!.role : none
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(initials).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("Company ID \(companyId) · \(role)").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CSBConfig) -> some View {
        let grade = resp?.grade ?? none
        let m = resp?.metrics
        // Honest live formatters: real field or the placeholder, never an invented literal.
        let tender: String = m?.tenderAcceptance.map { String(format: "%.1f%%", $0) } ?? none
        let completion: String = m?.completionRate.map { String(format: "%.1f%%", $0) } ?? none
        let loads: String = m?.totalLoads.map(String.init) ?? none
        _ = completion  // live field retained on the decode struct; not surfaced in this layout
        let delivered: String = m?.deliveredCount.map(String.init) ?? none
        let avgRate: String = m?.averageRate.map { "$\($0)" } ?? none
        let state: String = (resp == nil) ? none : "LIVE"

        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scoreAxis:
                return [
                    ("GRADE",      grade,      "composite axis · §9.5",   grade == none ? .secondary : .green),
                    ("TENDER",     tender,     "acceptance",              tender == none ? .secondary : .green),
                    ("LOADS",      loads,      "period aggregate",        loads == none ? .secondary : .blue),
                    ("STATE",      state,      c.statusBadge,             state == "LIVE" ? .green : .secondary),
                ]
            case .profileTier:
                // No tier / EIN / pillar-boost source behind getScorecard — honest "—".
                return [
                    ("TIER",       none,       "no tier source",          .secondary),
                    ("EIN",        none,       "no source",               .secondary),
                    ("GRADE",      grade,      "payor pillar",            grade == none ? .secondary : .green),
                    ("EFFECT",     none,       "no pillar-boost source",  .secondary),
                ]
            case .document:
                // No document-cabinet source behind getScorecard — honest "—".
                return [
                    ("DOC",        none,       "no document source",      .secondary),
                    ("STATE",      none,       c.statusBadge,             .secondary),
                    ("RUNWAY",     none,       "no expiry source",        .secondary),
                    ("OWNER",      none,       "no source",               .secondary),
                ]
            case .analytic:
                // DSO / RPM are NOT in getScorecard — honest "—". averageRate is the
                // only live rate field (avg per load, not per-mile).
                return [
                    ("DSO",        none,       "no DSO source",           .secondary),
                    ("TENDER",     tender,     "acceptance",              tender == none ? .secondary : .green),
                    ("AVG RATE",   avgRate,    "avg per load · period",   avgRate == none ? .secondary : .blue),
                    ("RPM",        none,       "no per-mile source",      .secondary),
                ]
            case .settlement:
                // Per-invoice settlement line-item is a confirmed backend gap.
                // No invented invoice / chain / NET-30 / book literals.
                return [
                    ("INVOICE",    none,       "per-invoice backend gap", .secondary),
                    ("CHAIN",      none,       "no source",               .secondary),
                    ("STATE",      none,       c.statusBadge,             .secondary),
                    ("BOOK",       none,       "no source",               .secondary),
                ]
            case .onboarding:
                // No onboarding-step ledger behind getScorecard — honest "—".
                return [
                    ("STEPS",      none,       "no step source",          .secondary),
                    ("STATE",      none,       c.statusBadge,             .secondary),
                    ("CLOSED",     none,       "no source",               .secondary),
                    ("OWNER",      none,       "no source",               .secondary),
                ]
            case .compliance:
                // No per-compliance-row source behind getScorecard — honest "—".
                return [
                    ("AUTH",       none,       "no auth source",          .secondary),
                    ("STATE",      none,       c.statusBadge,             .secondary),
                    ("DISPUTES",   none,       "no source",               .secondary),
                    ("CARGO",      none,       "no source",               .secondary),
                ]
            case .quarter:
                // No per-quarter rollup behind getScorecard — only the live
                // period aggregate (loads delivered) is real; gross / 1099 are gaps.
                return [
                    ("QUARTER",    none,       "no quarter rollup",       .secondary),
                    ("DELIVERED",  delivered,  "period · live",           delivered == none ? .secondary : .green),
                    ("1099-NEC",   none,       "no source",               .secondary),
                    ("STATE",      none,       c.statusBadge,             .secondary),
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

    // Per-invoice settlement is a confirmed backend gap — surface it honestly
    // rather than inventing a $1,805 / INV-…7E / 12d-outstanding line item.
    private var settlementGapCard: some View {
        EusoEmptyState(
            systemImage: "doc.text.magnifyingglass",
            title: "No per-invoice settlement",
            subtitle: "Per-invoice settlement lines are not available for this payor yet. Aggregate payor health is still shown above.",
            comingSoon: true
        )
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .scoreAxis:   return "Composite axis is pinned to §9.5 shipper books. Refresh with the next QC cycle."
            case .profileTier: return "Tier criteria (§13.5) are not carried on this scorecard. Reconfirm on the source-of-record before you price off the tier."
            case .document:    return "The document cabinet (§387.7) is not carried on this scorecard. Open the document service for COI runway."
            case .analytic:    return "Tender acceptance and average rate are live. DSO and RPM are not carried on this scorecard — read them off the settlement ledger."
            case .settlement:  return "Per-invoice settlement is not available on this screen yet. Open settlements for the live ledger."
            case .onboarding:  return "The onboarding-step ledger is not carried on this scorecard. Open onboarding for step state."
            case .compliance:  return "Per-compliance-row detail (§387 §388) is not carried on this scorecard. Open the compliance service."
            case .quarter:     return "Quarterly rollup is not carried on this scorecard. Only the live period aggregate is shown here — do not read it as a quarter close."
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
        // The current user is the shipper of record; derive the id from the
        // authenticated session (numeric ids only), else 0 — never a persona.
        let sid = Int(session.user?.id ?? "") ?? 0
        do {
            resp = try await EusoTripAPI.shared.query(
                "shipperScorecard.getScorecard",
                input: In(shipperId: sid, periodDays: 90)
            )
        } catch { /* leave resp nil → honest "—" placeholders */ }
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
