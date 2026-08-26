//
//  805_VesselLossPrevention.swift
//  EusoTrip - Vessel Operator - Loss Prevention.
//
//  Claim values remain dimensioned by ISO currency. Prevention savings and
//  prevention counts render as not modeled when the server says so.
//

import SwiftUI

private struct MetricTruth805: Decodable {
    struct Provenance: Decodable {
        let source: String?
        let observedAt: String?
        let computedAt: String?
        let basis: String?
    }
    let valueState: String
    let accessState: String?
    let trackingState: String
    let provenance: Provenance
    let reason: String?
}
private struct MoneyBucket805: Decodable { let currency: String; let amount: Double }
private struct AverageBucket805: Decodable { let currency: String; let amount: Double; let count: Int }

private struct LossDashboard805: Decodable {
    struct Metrics: Decodable {
        let totalLosses: Int
        let lossValue: Double?
        let lossValueCurrency: String?
        let totalsByCurrency: [MoneyBucket805]
        let unvaluedLossCount: Int
        let preventedLosses: Int?
        let preventionSavings: Double?
        let preventionSavingsCurrency: String?
        let lossRatio: Double?
        let lossRatioBasis: String
        let trendDirection: String?
    }
    struct Alert: Decodable, Identifiable {
        let id: String; let severity: String; let message: String; let lane: String?; let createdAt: String
    }
    struct RiskLane: Decodable, Identifiable {
        struct States: Decodable { let totalValue: MetricTruth805; let riskScore: MetricTruth805 }
        let lane: String
        let lossCount: Int
        let totalValue: Double?
        let totalValueCurrency: String?
        let totalsByCurrency: [MoneyBucket805]
        let riskScore: Double?
        let riskBasis: String
        let metricStates: States
        var id: String { lane }
    }
    struct States: Decodable {
        let totalLosses: MetricTruth805; let lossValue: MetricTruth805
        let unvaluedLossCount: MetricTruth805?
        let preventedLosses: MetricTruth805; let preventionSavings: MetricTruth805
        let lossRatio: MetricTruth805; let trendDirection: MetricTruth805
    }
    struct Provenance: Decodable {
        let source: String
        let recordKind: String
        let scope: String
        let transportMode: String?
        let observedAt: String?
        let computedAt: String
    }
    let transportMode: String?
    let metrics: Metrics
    let alerts: [Alert]
    let topRiskLanes: [RiskLane]
    let metricStates: States
    let provenance: Provenance
}

private struct LossAnalysis805: Decodable {
    struct Row: Decodable, Identifiable {
        struct States: Decodable {
            let claimCount: MetricTruth805; let totalValue: MetricTruth805
            let avgValue: MetricTruth805; let trend: MetricTruth805
        }
        let group: String
        let claimCount: Int
        let totalValue: Double?
        let totalValueCurrency: String?
        let totalsByCurrency: [MoneyBucket805]
        let averagesByCurrency: [AverageBucket805]
        let avgValue: Double?
        let unvaluedCount: Int
        let trend: String?
        let metricStates: States
        var id: String { group }
    }
    struct Provenance: Decodable {
        let source: String
        let recordKind: String
        let derivation: String
        let transportMode: String?
        let observedAt: String?
        let computedAt: String
    }
    let groupBy: String; let period: String; let transportMode: String?; let periodStart: String
    let data: [Row]; let recommendations: [String]; let unclassifiedCount: Int; let provenance: Provenance
}

struct VesselLossPreventionScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselLossPreventionBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselLossPreventionBody: View {
    @Environment(\.palette) private var palette
    @State private var dashboard: LossDashboard805?
    @State private var analysis: LossAnalysis805?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Loss prevention").font(.system(size: 30, weight: .bold)).foregroundStyle(palette.textPrimary)
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading loss evidence...").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let loadError {
                    LifecycleCard(accentDanger: true) { Text(loadError).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let dashboard, let analysis {
                    hero(dashboard)
                    causeCard(analysis)
                    Text("RISK ALERTS · CLAIM EVIDENCE").font(EType.micro).foregroundStyle(palette.textTertiary)
                    alerts(dashboard)
                    contractBand(dashboard, analysis)
                    HStack(spacing: 8) {
                        CTAButton(title: "Refresh alerts", action: { Task { await load() } }, trailingIcon: "bell")
                        secondaryButton805(title: "Refresh analysis") { Task { await load() } }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            EusoTripBrandMark(size: 12).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · LOSS PREVENTION").font(.system(size: 9, weight: .heavy))
                .tracking(1).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("12 MO").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
        }
    }

    private func hero(_ value: LossDashboard805) -> some View {
        let savings = money(value.metrics.preventionSavings,
                            currency: value.metrics.preventionSavingsCurrency,
                            buckets: [], truth: value.metricStates.preventionSavings)
        return RimCard805 {
            VStack(alignment: .leading, spacing: 8) {
                Text("PHYSICAL-LOSS CLAIM VALUE").font(EType.micro).foregroundStyle(palette.textTertiary)
                Text(money(value.metrics.lossValue, currency: value.metrics.lossValueCurrency,
                           buckets: value.metrics.totalsByCurrency, truth: value.metricStates.lossValue))
                    .font(.system(size: 28, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption(value.metricStates.lossValue)).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                Divider().overlay(palette.borderFaint)
                HStack {
                    metric("LOSSES", count(value.metrics.totalLosses, truth: value.metricStates.totalLosses))
                    metric("LOSS RATIO", percent(value.metrics.lossRatio, truth: value.metricStates.lossRatio))
                    metric("TREND", trend(value.metrics.trendDirection, truth: value.metricStates.trendDirection))
                }
                Text("Prevention savings · \(savings)")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(caption(value.metricStates.preventionSavings)).font(.system(size: 10)).foregroundStyle(Brand.warning)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(EType.micro).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func causeCard(_ value: LossAnalysis805) -> some View {
        RimCard805 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("LOSS BY \(value.groupBy.uppercased()) · CLAIM COUNT SHARE")
                        .font(EType.micro).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(value.period.uppercased()).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                if value.data.isEmpty {
                    Text("No grouped physical-loss observations in this period.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                } else {
                    let totalCount = value.data.reduce(0) { $0 + $1.claimCount }
                    let hasCompleteCountAccess = value.data.allSatisfy {
                        metricUnavailableLabel($0.metricStates.claimCount) == nil
                    }
                    ForEach(value.data.prefix(6)) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.group).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text("\(count(row.claimCount, truth: row.metricStates.claimCount)) claims · \(claimShare(row.claimCount, total: totalCount, truth: row.metricStates.claimCount, hasCompleteDenominator: hasCompleteCountAccess))")
                                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Text(money(row.totalValue, currency: row.totalValueCurrency,
                                       buckets: row.totalsByCurrency, truth: row.metricStates.totalValue))
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                                .multilineTextAlignment(.trailing)
                        }
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func alerts(_ value: LossDashboard805) -> some View {
        if value.alerts.isEmpty {
            EusoEmptyState(systemImage: "bell.slash", title: "No alert observations",
                           subtitle: "No open major or critical physical-loss claims were returned.")
        } else {
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(Array(value.alerts.prefix(5).enumerated()), id: \.element.id) { index, alert in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.message).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text("\(alert.lane ?? "lane unavailable") · recorded \(alert.createdAt)")
                                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Text(alert.severity.uppercased()).font(EType.micro).foregroundStyle(Brand.warning)
                        }.padding(.vertical, 10)
                        if index < min(value.alerts.count, 5) - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private func contractBand(_ dashboard: LossDashboard805, _ analysis: LossAnalysis805) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dashboard calculated \(dashboard.provenance.computedAt)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Analysis calculated \(analysis.provenance.computedAt)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Mode scope · \((dashboard.transportMode ?? dashboard.provenance.transportMode ?? "unknown").uppercased())")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Dashboard risk lanes retained: \(dashboard.topRiskLanes.count)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            if let unavailable = metricUnavailableLabel(dashboard.metricStates.unvaluedLossCount) {
                Text("Unvalued loss coverage · \(unavailable)")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            } else if dashboard.metrics.unvaluedLossCount > 0 {
                Text("Partial value coverage: \(dashboard.metrics.unvaluedLossCount) claims lack amount or ISO currency.")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func count(_ value: Int, truth: MetricTruth805) -> String {
        metricUnavailableLabel(truth) ?? "\(value)"
    }
    private func percent(_ value: Double?, truth: MetricTruth805) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value else { return "Unavailable" }
        return String(format: "%.1f%%", value * 100)
    }
    private func trend(_ value: String?, truth: MetricTruth805) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        return value?.capitalized ?? "Unavailable"
    }
    private func claimShare(
        _ count: Int,
        total: Int,
        truth: MetricTruth805,
        hasCompleteDenominator: Bool
    ) -> String {
        guard metricUnavailableLabel(truth) == nil, hasCompleteDenominator, total > 0 else {
            return "No denominator"
        }
        return "\(Int((Double(count) / Double(total) * 100).rounded()))%"
    }
    private func money(_ value: Double?, currency: String?, buckets: [MoneyBucket805], truth: MetricTruth805) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        if !buckets.isEmpty { return buckets.map { formatted($0.amount, currency: $0.currency) }.joined(separator: " · ") }
        guard let value, let currency else { return "Unavailable" }
        return formatted(value, currency: currency)
    }
    private func formatted(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency; formatter.currencyCode = currency; formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency) \(String(format: "%.0f", value))"
    }
    private func caption(_ truth: MetricTruth805) -> String {
        if let unavailable = metricUnavailableLabel(truth) {
            return truth.reason ?? unavailable
        }
        switch truth.valueState {
        case "measured": return truth.provenance.basis ?? "Measured"
        case "measured_by_dimension": return truth.reason ?? "Measured by currency"
        case "partial": return truth.reason ?? "Partial source coverage"
        case "no_observations": return truth.reason ?? "No scoped observations"
        case "not_modeled": return truth.reason ?? "Not modeled"
        default: return "Metric state unavailable"
        }
    }

    private func metricUnavailableLabel(_ truth: MetricTruth805) -> String? {
        guard truth.accessState == "granted" else {
            return truth.accessState == "restricted" ? "Restricted" : "Access unknown"
        }
        guard truth.trackingState == "tracked" else { return "Not tracked" }
        switch truth.valueState {
        case "not_modeled": return "Not modeled"
        case "no_observations": return "No observations"
        case "measured", "measured_by_dimension", "partial": return nil
        default: return "Metric state unavailable"
        }
    }

    private func metricUnavailableLabel(_ truth: MetricTruth805?) -> String? {
        guard let truth else { return "Access unknown" }
        return metricUnavailableLabel(truth)
    }

    private func load() async {
        loading = true
        loadError = nil
        struct DashboardInput: Encodable { let transportMode: String }
        struct AnalysisInput: Encodable { let transportMode: String; let groupBy: String; let period: String }
        do {
            async let dashboardResult: LossDashboard805 =
                EusoTripAPI.shared.query(
                    "freightClaims.getLossPreventionDashboard",
                    input: DashboardInput(transportMode: "VESSEL")
                )
            async let analysisResult: LossAnalysis805 =
                EusoTripAPI.shared.query("freightClaims.getLossPreventionAnalysis",
                                         input: AnalysisInput(transportMode: "VESSEL", groupBy: "commodity", period: "year"))
            (dashboard, analysis) = try await (dashboardResult, analysisResult)
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func secondaryButton805(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44).background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }
}

private struct RimCard805<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

#Preview("805 · Loss Prevention · Night") {
    VesselLossPreventionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("805 · Loss Prevention · Light") {
    VesselLossPreventionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
