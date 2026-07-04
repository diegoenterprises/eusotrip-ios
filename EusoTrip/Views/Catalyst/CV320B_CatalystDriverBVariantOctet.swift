//
//  CV320B_CatalystDriverBVariantOctet.swift
//  EusoTrip — Catalyst · Driver B-variant deep-drill octet (320B-327B).
//
//  Surfaces:
//    320B Catalyst Scorecard Axis Detail            (§9.1)
//    321B Catalyst Profile Tier Detail              (§13)
//    322B Catalyst Document Detail
//    323B Catalyst Driver Analytic Detail           (§395.8)
//    324B Catalyst Driver Settlement Detail
//    325B Catalyst Driver Onboarding Step Detail
//    326B Catalyst Compliance Row Detail
//    327B Catalyst Driver Quarter Detail
//
//  Driver counterparts to CV330B-CV337B. Single bundled file. Body binds
//  to `drivers.getPerformanceMetrics` (→ DriversAPI.PerformanceScorecard)
//  for every live KPI, and resolves the real driver identity (name + id)
//  from `catalysts.getMyDrivers`. There is no `drivers.getScorecard` proc
//  and no driver-side tier / per-doc compliance / settlement-line-item /
//  quarter-rollup source — those sub-fields render an honest "—" rather
//  than a fabricated literal. Bottom nav frozen.
//

import SwiftUI

enum CatalystDriverBKind: String {
    case scoreAxis, profileTier, document, analytic, settlement, onboarding, compliance, quarter
}

private struct CDBConfig {
    let eyebrow: String
    let citation: String
    let title: String
    /// Static subhead suffix — the real driver id is prepended at render
    /// time once `catalysts.getMyDrivers` resolves it.
    let subheadSuffix: String
    let pillCopy: String
}

private extension CatalystDriverBKind {
    var config: CDBConfig {
        switch self {
        case .scoreAxis:
            return .init(eyebrow: "CATALYST · DRIVER · SCORECARD AXIS",
                         citation: "§9.1 · COMPOSITE",
                         title: "Axis detail",
                         subheadSuffix: "§9.1 · scorecard composite",
                         pillCopy: "Catalyst rates driver · same company both sides · §9.1 composite from performance metrics")
        case .profileTier:
            return .init(eyebrow: "CATALYST · DRIVER · TIER",
                         citation: "§13 · TIER",
                         title: "Tier detail",
                         subheadSuffix: "§13 · tier criteria",
                         pillCopy: "Catalyst rates driver · same company both sides · §13 tier criteria")
        case .document:
            return .init(eyebrow: "CATALYST · DRIVER · DOCUMENT",
                         citation: "DOCUMENT",
                         title: "Document detail",
                         subheadSuffix: "driver document file",
                         pillCopy: "Catalyst archives driver docs · same company both sides · pre-employment document file")
        case .analytic:
            return .init(eyebrow: "CATALYST · DRIVER · ANALYTIC",
                         citation: "§395.8 · LIVE",
                         title: "Analytic detail",
                         subheadSuffix: "§395.8 · ELD record",
                         pillCopy: "Catalyst tracks driver KPIs · same company both sides · §395.8 ELD record")
        case .settlement:
            return .init(eyebrow: "CATALYST · DRIVER · SETTLEMENT",
                         citation: "SETTLEMENT",
                         title: "Settlement detail",
                         subheadSuffix: "settlement line items",
                         pillCopy: "Catalyst pays driver · same company both sides · settlement line items")
        case .onboarding:
            return .init(eyebrow: "CATALYST · DRIVER · STEP DETAIL",
                         citation: "ONBOARDING",
                         title: "Step detail",
                         subheadSuffix: "onboarding step",
                         pillCopy: "Catalyst onboards driver · same company both sides · controlled-substances file")
        case .compliance:
            return .init(eyebrow: "CATALYST · DRIVER · COMPLIANCE ROW",
                         citation: "COMPLIANCE",
                         title: "Compliance row",
                         subheadSuffix: "compliance row",
                         pillCopy: "Catalyst monitors driver · same company both sides · random-testing pool")
        case .quarter:
            return .init(eyebrow: "CATALYST · DRIVER · QUARTER DETAIL",
                         citation: "QUARTER",
                         title: "Quarter detail",
                         subheadSuffix: "quarter rollup",
                         pillCopy: "Catalyst archives driver quarter rollup · same company both sides · Schedule C close")
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
    @State private var scorecard: DriversAPI.PerformanceScorecard?
    @State private var driverId: String = ""
    @State private var driverName: String = ""

    private static let dash = "—"

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

    // MARK: - Composite grade (canonical 320 formula, real metrics only)

    private var grade: String {
        guard let m = scorecard?.metrics else { return Self.dash }
        let onTime = max(0.0, min(1.0, m.onTimeDeliveryRate / 100))
        let completion = max(0.0, min(1.0, m.hosCompliance / 100))
        let loadsTerm: Double = {
            let n = Double(max(0, m.totalLoads))
            let den = log10(50.0)
            return den > 0 ? log10(n + 1.0) / den : 0
        }()
        let composite = onTime * 0.5 + completion * 0.3 + loadsTerm * 0.2
        switch composite {
        case 0.95...:     return "A+"
        case 0.90..<0.95: return "A"
        case 0.85..<0.90: return "A−"
        case 0.80..<0.85: return "B+"
        case 0.75..<0.80: return "B"
        case 0.70..<0.75: return "B−"
        case 0.60..<0.70: return "C"
        case 0.50..<0.60: return "D"
        default:          return "F"
        }
    }

    private var monogram: String {
        let parts = driverName.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "—" : String(initials.prefix(2))
    }

    private var idLabel: String { driverId.isEmpty ? Self.dash : driverId }

    private func header(_ c: CDBConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("\(idLabel) · \(c.subheadSuffix)").font(EType.caption).foregroundStyle(palette.textSecondary)
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
                    .overlay(Text(grade).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(idLabel).font(.caption2.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text(c.citation).font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private var identityRow: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(monogram).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(driverName.isEmpty ? Self.dash : driverName) · \(idLabel)").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    // No driver-side company / hire-date / ACH source in
                    // getMyDrivers or getPerformanceMetrics — honest dash.
                    Text("Company \(Self.dash) · hired \(Self.dash) · ACH \(Self.dash)").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func kpiGrid(_ c: CDBConfig) -> some View {
        let m = scorecard?.metrics
        // Honest formatters — return "—" when the metric is absent.
        func pct0(_ v: Double?) -> String { v.map { String(format: "%.0f%%", $0) } ?? Self.dash }
        func pct1(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0) } ?? Self.dash }
        func intStr(_ v: Int?) -> String { v.map(String.init) ?? Self.dash }

        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .scoreAxis:
                return [
                    ("GRADE",   grade,                            "composite axis · §9.1", .green),
                    ("ON-TIME", pct1(m?.onTimeDeliveryRate),      "on-time delivery rate", .green),
                    ("HOS",     pct0(m?.hosCompliance),           "§395.8 compliance",     .green),
                    ("LOADS",   intStr(m?.totalLoads),            "this period",           .blue),
                ]
            case .profileTier:
                return [
                    // No driver-side tier proc — honest dash, not "GOLD".
                    ("TIER",     Self.dash,                       "no tier source",        .gray),
                    ("CRITERIA", "§13",                           "tier criteria",         .blue),
                    ("SAFETY",   pct0(m?.safetyScore),            "safety score",          .green),
                    ("RATING",   (m?.customerRating).map { String(format: "%.1f", $0) } ?? Self.dash, "customer rating", .blue),
                ]
            case .document:
                // No per-document compliance source — honest dashes, no
                // fabricated §382.301 MISSING row.
                return [
                    ("DOC",    Self.dash, "no document source",  .gray),
                    ("STATE",  Self.dash, "no status source",    .gray),
                    ("RENEW",  Self.dash, "no expiry source",    .gray),
                    ("OWNER",  Self.dash, "no owner source",     .gray),
                ]
            case .analytic:
                return [
                    ("ON-TIME", pct1(m?.onTimeDeliveryRate),      "delivery pillar",       .green),
                    ("ELD",     "§395.8",                         "live record",           .blue),
                    ("PASS",    pct0(m?.inspectionPassRate),      "inspection · §396",     .green),
                    ("MILES",   (m?.totalMiles).map { String(format: "%.0f", $0) } ?? Self.dash, "miles this period", .blue),
                ]
            case .settlement:
                // No per-allocation settlement line-item source here —
                // honest dashes, no fabricated $1,805 / ACH ····6411.
                return [
                    ("AMOUNT", Self.dash, "no line-item source", .gray),
                    ("CHAIN",  Self.dash, "no POD source",       .gray),
                    ("STATE",  Self.dash, "no status source",    .gray),
                    ("BOOK",   Self.dash, "no ledger source",    .gray),
                ]
            case .onboarding:
                // No onboarding-step source — honest dashes, no fabricated
                // §382 drug-screen MISSING row.
                return [
                    ("STEP",   Self.dash, "no step source",      .gray),
                    ("STATE",  Self.dash, "no status source",    .gray),
                    ("RENEW",  Self.dash, "no schedule source",  .gray),
                    ("OWNER",  Self.dash, "no owner source",     .gray),
                ]
            case .compliance:
                // No per-row compliance source — honest dashes, no
                // fabricated §382.305 MISSING row.
                return [
                    ("ROW",    Self.dash, "no row source",       .gray),
                    ("STATE",  Self.dash, "no status source",    .gray),
                    ("POOL",   "§382.305", "random-test pillar", .blue),
                    ("OWNER",  Self.dash, "no owner source",     .gray),
                ]
            case .quarter:
                // No per-quarter rollup source — honest dashes, no
                // fabricated Q1 94.0% close.
                return [
                    ("QUARTER",  Self.dash, "no quarter source",   .gray),
                    ("OTP",      Self.dash, "no rollup source",    .gray),
                    ("SCHEDULE", Self.dash, "no schedule source",  .gray),
                    ("STATE",    Self.dash, "no status source",    .gray),
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
        let m = scorecard?.metrics
        let copy: String = {
            switch kind {
            case .scoreAxis:
                if let m {
                    return "Composite grade \(grade) from getPerformanceMetrics — on-time \(String(format: "%.1f", m.onTimeDeliveryRate))%, HOS \(String(format: "%.0f", m.hosCompliance))%, \(m.totalLoads) loads. Refresh with the next cycle."
                }
                return "Scorecard composite (§9.1) loads from getPerformanceMetrics. No metrics in this window yet."
            case .profileTier:
                return "No driver-side tier proc is wired yet. Tier (§13) renders \(Self.dash) until a tier source ships."
            case .document:
                return "No per-document compliance source is wired yet. Document rows render \(Self.dash) until one ships."
            case .analytic:
                if let m {
                    return "On-time \(String(format: "%.1f", m.onTimeDeliveryRate))%, inspection pass \(String(format: "%.0f", m.inspectionPassRate))% (§395.8 / §396). Hold the cadence."
                }
                return "Analytic pillars (§395.8) load from getPerformanceMetrics. No metrics in this window yet."
            case .settlement:
                return "No per-allocation settlement line-item source is wired here. Amount / chain / book render \(Self.dash) until one ships."
            case .onboarding:
                return "No onboarding-step source is wired yet. Step rows render \(Self.dash) until one ships."
            case .compliance:
                return "No per-row compliance source is wired yet. Compliance rows render \(Self.dash) until one ships."
            case .quarter:
                return "No per-quarter rollup source is wired yet. Quarter close renders \(Self.dash) until one ships."
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
        // Resolve the real driver (name + id) from the catalyst's roster,
        // then bind live KPIs from drivers.getPerformanceMetrics. There is
        // no drivers.getScorecard proc — getPerformanceMetrics is the
        // canonical scorecard surface.
        do {
            let roster = try await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)
            guard let primary = roster.first else { return }
            driverId = primary.id
            driverName = primary.name
            scorecard = try await EusoTripAPI.shared.drivers.getPerformanceMetrics(
                driverId: primary.id,
                period: .quarter
            )
        } catch { /* leave honest dashes */ }
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
