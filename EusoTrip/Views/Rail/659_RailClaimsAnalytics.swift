//
//  659_RailClaimsAnalytics.swift
//  EusoTrip - Rail Engineer - Claims Analytics.
//
//  freightClaims.getClaimsAnalytics consumer. Values remain grouped by ISO
//  currency and every modeled metric retains its server truth state.
//

import SwiftUI

struct RailClaimsAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailClaimsAnalyticsBody() } nav: {
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

private struct MetricTruth659: Decodable {
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

private struct MoneyBucket659: Decodable { let currency: String; let amount: Double }
private struct AverageBucket659: Decodable { let currency: String; let amount: Double; let count: Int }

private struct ClaimsAnalytics659: Decodable {
    struct CountState: Decodable { let count: MetricTruth659 }
    struct StatusRow: Decodable {
        let status: String
        let count: Int
        let metricStates: CountState?
    }
    struct ValueRow: Decodable {
        struct States: Decodable { let count: MetricTruth659; let value: MetricTruth659 }
        let type: String?
        let month: String?
        let count: Int
        let value: Double?
        let currency: String?
        let totalsByCurrency: [MoneyBucket659]
        let metricState: MetricTruth659
        let metricStates: States?
    }
    struct CarrierRow: Decodable {
        struct States: Decodable { let claimCount: MetricTruth659; let totalValue: MetricTruth659 }
        let carrier: String
        let claimCount: Int
        let totalValue: Double?
        let currency: String?
        let totalsByCurrency: [MoneyBucket659]
        let metricState: MetricTruth659
        let metricStates: States?
    }
    struct MetricStates: Decodable {
        let frequency: MetricTruth659
        let avgCost: MetricTruth659
        let unvaluedCount: MetricTruth659?
        let avgResolutionDays: MetricTruth659
        let recoveryRate: MetricTruth659
    }
    struct Provenance: Decodable {
        let source: String
        let recordKind: String
        let scope: String
        let transportMode: String?
        let observedAt: String?
        let computedAt: String
    }

    let period: String
    let transportMode: String?
    let periodStart: String
    let frequency: Int
    let avgCost: Double?
    let avgCostCurrency: String?
    let totalsByCurrency: [MoneyBucket659]
    let unvaluedCount: Int
    let avgResolutionDays: Double?
    let avgCostByCurrency: [AverageBucket659]
    let byType: [ValueRow]
    let byMonth: [ValueRow]
    let byStatus: [StatusRow]
    let topCarriers: [CarrierRow]
    let recoveryRate: Double?
    let recoveryRateBasis: String
    let metricStates: MetricStates
    let provenance: Provenance
}

private struct RailClaimsAnalyticsBody: View {
    @Environment(\.palette) private var palette
    @State private var data: ClaimsAnalytics659?
    @State private var loading = true
    @State private var loadError: String?
    @State private var ack: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading analytics...").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let loadError {
                    LifecycleCard(accentDanger: true) { Text(loadError).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let data {
                    hero(data)
                    kpis(data)
                    statusCard(data)
                    provenanceCard(data)
                    if let ack { Text(ack).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    actions(data)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · CLAIMS ANALYTICS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("CLAIMS · YTD").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            HStack {
                Image(systemName: "chevron.left").foregroundStyle(palette.textPrimary)
                Text("Analytics").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func hero(_ value: ClaimsAnalytics659) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("PAID STATUS / ALL SCOPED CLAIMS").font(EType.micro).foregroundStyle(palette.textTertiary)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(percent(value.recoveryRate, truth: value.metricStates.recoveryRate))
                            .font(.system(size: 32, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(caption(value.metricStates.recoveryRate)).font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary).lineLimit(3)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("AVERAGE CLAIM VALUE").font(EType.micro).foregroundStyle(palette.textTertiary)
                        Text(averageCost(value)).font(.system(size: 17, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary).multilineTextAlignment(.trailing)
                        Text(caption(value.metricStates.avgCost)).font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary).multilineTextAlignment(.trailing).lineLimit(3)
                    }.frame(maxWidth: 170, alignment: .trailing)
                }
            }
        }
    }

    private func kpis(_ value: ClaimsAnalytics659) -> some View {
        HStack(spacing: Space.s2) {
            tile("RECOVERY", percent(value.recoveryRate, truth: value.metricStates.recoveryRate), caption(value.metricStates.recoveryRate))
            tile("CLAIMS", count(value.frequency, truth: value.metricStates.frequency), caption(value.metricStates.frequency))
            tile("RESOLVE", duration(value.avgResolutionDays, truth: value.metricStates.avgResolutionDays), caption(value.metricStates.avgResolutionDays))
        }
    }

    private func tile(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(label).font(EType.micro).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary).lineLimit(2).minimumScaleFactor(0.65)
            Text(sub).font(.system(size: 9)).foregroundStyle(palette.textTertiary).lineLimit(3)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statusCard(_ value: ClaimsAnalytics659) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("BY STATUS").font(EType.micro).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("COUNT ONLY").font(EType.micro).foregroundStyle(palette.textTertiary)
            }
            if value.byStatus.isEmpty {
                EusoEmptyState(systemImage: "chart.bar.doc.horizontal", title: "No status observations",
                               subtitle: caption(value.metricStates.frequency))
            } else {
                ForEach(value.byStatus, id: \.status) { row in
                    let countLabel = count(row.count, truth: row.metricStates?.count)
                    let shareLabel = share(
                        row.count,
                        total: value.frequency,
                        numeratorTruth: row.metricStates?.count,
                        denominatorTruth: value.metricStates.frequency
                    )
                    HStack {
                        Text(row.status.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("\(countLabel) · \(shareLabel)")
                            .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    }
                    Divider().overlay(palette.borderFaint)
                }
                Text("The endpoint exposes status counts, not status-level monetary exposure or recovered amounts.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func provenanceCard(_ value: ClaimsAnalytics659) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOURCE · \(value.provenance.source)").font(EType.micro).foregroundStyle(palette.textTertiary)
            Text("Snapshot calculated \(value.provenance.computedAt) · \(value.provenance.scope.replacingOccurrences(of: "_", with: " ")) scope")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Mode scope · \((value.transportMode ?? value.provenance.transportMode ?? "unknown").uppercased())")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            if let unavailable = metricUnavailableLabel(value.metricStates.unvaluedCount) {
                Text("Unvalued claim coverage · \(unavailable)")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            } else if value.unvaluedCount > 0 {
                Text("Partial monetary coverage: \(value.unvaluedCount) records lack a usable amount or ISO currency.")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func actions(_ value: ClaimsAnalytics659) -> some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Open report", action: {
                if let unavailable = metricUnavailableLabel(value.metricStates.frequency) {
                    ack = "Claim availability is \(unavailable.lowercased()); report export is unavailable."
                } else {
                    ack = value.frequency > 0
                        ? "Report export runs per claim. Open a claim to generate its export."
                        : "No claim observations are available for a report."
                }
            })
            RailSecondaryActionButton(
                title: "Details", sheetTitle: "Analytics contract",
                lines: ["Period: \(value.period)",
                        "Claims: \(count(value.frequency, truth: value.metricStates.frequency))",
                        "Recovery: \(percent(value.recoveryRate, truth: value.metricStates.recoveryRate))",
                        "Average value: \(averageCost(value))",
                        "Calculated: \(value.provenance.computedAt)"],
                systemImage: "info.circle"
            )
        }
    }

    private func count(_ value: Int, truth: MetricTruth659) -> String {
        metricUnavailableLabel(truth) ?? "\(value)"
    }

    private func count(_ value: Int, truth: MetricTruth659?) -> String {
        guard let truth else { return "Access unknown" }
        return count(value, truth: truth)
    }

    private func percent(_ value: Double?, truth: MetricTruth659) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value else { return "Unavailable" }
        return String(format: "%.1f%%", value * 100)
    }

    private func duration(_ value: Double?, truth: MetricTruth659) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value else { return "Unavailable" }
        return String(format: "%.1f d", value)
    }

    private func averageCost(_ value: ClaimsAnalytics659) -> String {
        let truth = value.metricStates.avgCost
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        if !value.avgCostByCurrency.isEmpty {
            return value.avgCostByCurrency.map { money($0.amount, currency: $0.currency) }.joined(separator: " · ")
        }
        guard let amount = value.avgCost, let currency = value.avgCostCurrency else { return "Unavailable" }
        return money(amount, currency: currency)
    }

    private func money(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.0f", amount))"
    }

    private func caption(_ truth: MetricTruth659) -> String {
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

    private func metricUnavailableLabel(_ truth: MetricTruth659) -> String? {
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

    private func metricUnavailableLabel(_ truth: MetricTruth659?) -> String? {
        guard let truth else { return "Access unknown" }
        return metricUnavailableLabel(truth)
    }

    private func share(
        _ count: Int,
        total: Int,
        numeratorTruth: MetricTruth659?,
        denominatorTruth: MetricTruth659
    ) -> String {
        guard metricUnavailableLabel(numeratorTruth) == nil,
              metricUnavailableLabel(denominatorTruth) == nil else { return "No denominator" }
        guard total > 0 else { return "No denominator" }
        return "\(Int((Double(count) / Double(total) * 100).rounded()))%"
    }

    private func reload() async {
        loading = true
        loadError = nil
        struct Input: Encodable { let transportMode: String; let period: String }
        do {
            data = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimsAnalytics",
                input: Input(transportMode: "RAIL", period: "year")
            )
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

#Preview("659 · Rail Claims Analytics · Night") {
    RailClaimsAnalyticsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("659 · Rail Claims Analytics · Light") {
    RailClaimsAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
