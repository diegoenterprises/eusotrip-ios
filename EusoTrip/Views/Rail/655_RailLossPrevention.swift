//
//  655_RailLossPrevention.swift
//  EusoTrip - Rail Engineer - Loss Prevention.
//
//  Consumes both loss-prevention procedures without collapsing null, partial,
//  dimensioned, no-observation, or not-modeled metric states.
//

import SwiftUI

private struct MetricTruth655: Decodable {
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
private struct MoneyBucket655: Decodable { let currency: String; let amount: Double }
private struct AverageBucket655: Decodable { let currency: String; let amount: Double; let count: Int }

private struct LossPreventionDashboard655: Decodable {
    struct Metrics: Decodable {
        let totalLosses: Int
        let lossValue: Double?
        let lossValueCurrency: String?
        let totalsByCurrency: [MoneyBucket655]
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
        struct States: Decodable { let totalValue: MetricTruth655; let riskScore: MetricTruth655 }
        let lane: String
        let lossCount: Int
        let totalValue: Double?
        let totalValueCurrency: String?
        let totalsByCurrency: [MoneyBucket655]
        let riskScore: Double?
        let riskBasis: String
        let metricStates: States
        var id: String { lane }
    }
    struct States: Decodable {
        let totalLosses: MetricTruth655
        let lossValue: MetricTruth655
        let unvaluedLossCount: MetricTruth655?
        let preventedLosses: MetricTruth655
        let preventionSavings: MetricTruth655
        let lossRatio: MetricTruth655
        let trendDirection: MetricTruth655
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

private struct LossPreventionAnalysis655: Decodable {
    struct Row: Decodable, Identifiable {
        struct States: Decodable {
            let claimCount: MetricTruth655; let totalValue: MetricTruth655
            let avgValue: MetricTruth655; let trend: MetricTruth655
        }
        let group: String
        let claimCount: Int
        let totalValue: Double?
        let totalValueCurrency: String?
        let totalsByCurrency: [MoneyBucket655]
        let averagesByCurrency: [AverageBucket655]
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
    let groupBy: String
    let period: String
    let transportMode: String?
    let periodStart: String
    let data: [Row]
    let recommendations: [String]
    let unclassifiedCount: Int
    let provenance: Provenance
}

struct RailLossPreventionScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailLossPreventionBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct RailLossPreventionBody: View {
    @Environment(\.palette) private var palette
    @State private var dashboard: LossPreventionDashboard655?
    @State private var analysis: LossPreventionAnalysis655?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading loss evidence...").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let loadError {
                    LifecycleCard(accentDanger: true) { Text(loadError).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let dashboard, let analysis {
                    hero(dashboard)
                    kpis(dashboard)
                    hotspots(analysis)
                    preventionState(dashboard)
                    provenance(dashboard, analysis)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · LOSS PREVENTION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("12 MO").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Loss prevention").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
        }
    }

    private func hero(_ value: LossPreventionDashboard655) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("PHYSICAL-LOSS CLAIM VALUE").font(EType.micro).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(trend(value.metrics.trendDirection, truth: value.metricStates.trendDirection))
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textSecondary)
                }
                Text(money(value.metrics.lossValue, currency: value.metrics.lossValueCurrency,
                           buckets: value.metrics.totalsByCurrency, truth: value.metricStates.lossValue))
                    .font(.system(size: 27, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption(value.metricStates.lossValue)).font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary).lineLimit(3)
                HStack {
                    Text("Physical-loss claims / all scoped claims")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(percent(value.metrics.lossRatio, truth: value.metricStates.lossRatio))
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func kpis(_ value: LossPreventionDashboard655) -> some View {
        HStack(spacing: Space.s2) {
            tile("LOSSES", count(value.metrics.totalLosses, truth: value.metricStates.totalLosses),
                 caption(value.metricStates.totalLosses))
            tile("PREVENTED", optionalCount(value.metrics.preventedLosses, truth: value.metricStates.preventedLosses),
                 caption(value.metricStates.preventedLosses))
            tile("SAVINGS", money(value.metrics.preventionSavings,
                                   currency: value.metrics.preventionSavingsCurrency,
                                   buckets: [], truth: value.metricStates.preventionSavings),
                 caption(value.metricStates.preventionSavings))
        }
    }

    private func tile(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).font(EType.micro).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary).lineLimit(2).minimumScaleFactor(0.65)
            Text(sub).font(.system(size: 9)).foregroundStyle(palette.textTertiary).lineLimit(3)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func hotspots(_ value: LossPreventionAnalysis655) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("HOTSPOTS · BY \(value.groupBy.uppercased())").font(EType.micro).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(value.period.uppercased()).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            if value.data.isEmpty {
                EusoEmptyState(systemImage: "exclamationmark.triangle", title: "No hotspot observations",
                               subtitle: "No physical-loss groups were returned for this period.")
            } else {
                LifecycleCard {
                    VStack(spacing: 0) {
                        ForEach(Array(value.data.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: Space.s3) {
                                RoundedRectangle(cornerRadius: 10).fill(Brand.warning.opacity(0.14)).frame(width: 40, height: 40)
                                    .overlay(Image(systemName: "exclamationmark.triangle").foregroundStyle(Brand.warning))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.group).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                                    Text("\(count(row.claimCount, truth: row.metricStates.claimCount)) claims · \(trend(row.trend, truth: row.metricStates.trend))")
                                        .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                                }
                                Spacer()
                                Text(money(row.totalValue, currency: row.totalValueCurrency,
                                           buckets: row.totalsByCurrency, truth: row.metricStates.totalValue))
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                                    .multilineTextAlignment(.trailing)
                            }.padding(.vertical, 10)
                            if index < value.data.count - 1 { Divider().overlay(palette.borderFaint) }
                        }
                    }
                }
            }
        }
    }

    private func preventionState(_ value: LossPreventionDashboard655) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PREVENTION OUTCOMES").font(EType.micro).foregroundStyle(palette.textTertiary)
            Text("Prevented losses · \(optionalCount(value.metrics.preventedLosses, truth: value.metricStates.preventedLosses))")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(caption(value.metricStates.preventedLosses)).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Prevention savings · \(caption(value.metricStates.preventionSavings))")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func provenance(_ dashboard: LossPreventionDashboard655, _ analysis: LossPreventionAnalysis655) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOURCE · \(dashboard.provenance.source)").font(EType.micro).foregroundStyle(palette.textTertiary)
            Text("Dashboard calculated \(dashboard.provenance.computedAt)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Analysis calculated \(analysis.provenance.computedAt)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Mode scope · \((dashboard.transportMode ?? dashboard.provenance.transportMode ?? "unknown").uppercased())")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            if let unavailable = metricUnavailableLabel(dashboard.metricStates.unvaluedLossCount) {
                Text("Unvalued loss coverage · \(unavailable)")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            } else if dashboard.metrics.unvaluedLossCount > 0 {
                Text("Partial value coverage: \(dashboard.metrics.unvaluedLossCount) loss claims lack amount or ISO currency.")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s4).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func count(_ value: Int, truth: MetricTruth655) -> String {
        metricUnavailableLabel(truth) ?? "\(value)"
    }

    private func optionalCount(_ value: Int?, truth: MetricTruth655) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value else { return "Unavailable" }
        return "\(value)"
    }

    private func percent(_ value: Double?, truth: MetricTruth655) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value else { return "Unavailable" }
        return String(format: "%.1f%%", value * 100)
    }

    private func trend(_ value: String?, truth: MetricTruth655) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        return value?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Unavailable"
    }

    private func money(_ value: Double?, currency: String?, buckets: [MoneyBucket655], truth: MetricTruth655) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        if !buckets.isEmpty { return buckets.map { formatted($0.amount, currency: $0.currency) }.joined(separator: " · ") }
        guard let value, let currency else { return "Unavailable" }
        return formatted(value, currency: currency)
    }

    private func formatted(_ value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(currency) \(String(format: "%.0f", value))"
    }

    private func caption(_ truth: MetricTruth655) -> String {
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

    private func metricUnavailableLabel(_ truth: MetricTruth655) -> String? {
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

    private func metricUnavailableLabel(_ truth: MetricTruth655?) -> String? {
        guard let truth else { return "Access unknown" }
        return metricUnavailableLabel(truth)
    }

    private func reload() async {
        loading = true
        loadError = nil
        struct DashboardInput: Encodable { let transportMode: String }
        struct AnalysisInput: Encodable { let transportMode: String; let groupBy: String; let period: String }
        do {
            async let dashboardResult: LossPreventionDashboard655 =
                EusoTripAPI.shared.query(
                    "freightClaims.getLossPreventionDashboard",
                    input: DashboardInput(transportMode: "RAIL")
                )
            async let analysisResult: LossPreventionAnalysis655 =
                EusoTripAPI.shared.query("freightClaims.getLossPreventionAnalysis",
                                         input: AnalysisInput(transportMode: "RAIL", groupBy: "lane", period: "year"))
            (dashboard, analysis) = try await (dashboardResult, analysisResult)
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

#Preview("655 · Rail Loss Prevention · Night") {
    RailLossPreventionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("655 · Rail Loss Prevention · Light") {
    RailLossPreventionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
