//
//  811_VesselClaimsAnalytics.swift
//  EusoTrip - Vessel Operator - Claims Analytics.
//
//  The analytics contract is count-based for recovery and dimensioned by ISO
//  currency for money. This consumer never derives recovered money.
//

import SwiftUI

private struct MetricTruth811: Decodable {
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

private struct MoneyBucket811: Decodable { let currency: String; let amount: Double }
private struct AverageBucket811: Decodable { let currency: String; let amount: Double; let count: Int }

private struct Analytics811: Decodable {
    struct CountState: Decodable { let count: MetricTruth811 }
    struct TypeRow: Decodable {
        struct States: Decodable { let count: MetricTruth811; let value: MetricTruth811 }
        let type: String
        let count: Int
        let value: Double?
        let currency: String?
        let totalsByCurrency: [MoneyBucket811]
        let metricState: MetricTruth811
        let metricStates: States?
    }
    struct CarrierRow: Decodable {
        struct States: Decodable { let claimCount: MetricTruth811; let totalValue: MetricTruth811 }
        let carrier: String
        let claimCount: Int
        let totalValue: Double?
        let currency: String?
        let totalsByCurrency: [MoneyBucket811]
        let metricState: MetricTruth811
        let metricStates: States?
    }
    struct MonthRow: Decodable {
        struct States: Decodable { let count: MetricTruth811; let value: MetricTruth811 }
        let month: String
        let count: Int
        let value: Double?
        let currency: String?
        let totalsByCurrency: [MoneyBucket811]
        let metricState: MetricTruth811
        let metricStates: States?
    }
    struct StatusRow: Decodable { let status: String; let count: Int; let metricStates: CountState? }
    struct MetricStates: Decodable {
        let frequency: MetricTruth811
        let avgCost: MetricTruth811
        let unvaluedCount: MetricTruth811?
        let avgResolutionDays: MetricTruth811
        let recoveryRate: MetricTruth811
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
    let totalsByCurrency: [MoneyBucket811]
    let unvaluedCount: Int
    let avgResolutionDays: Double?
    let avgCostByCurrency: [AverageBucket811]
    let byType: [TypeRow]
    let byMonth: [MonthRow]
    let byStatus: [StatusRow]
    let topCarriers: [CarrierRow]
    let recoveryRate: Double?
    let recoveryRateBasis: String
    let metricStates: MetricStates
    let provenance: Provenance
}

struct VesselClaimsAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselClaimsAnalyticsBody() } nav: {
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

private struct VesselClaimsAnalyticsBody: View {
    @Environment(\.palette) private var palette
    @State private var analytics: Analytics811?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Claims analytics").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                if let analytics {
                    Text("\(analytics.period.uppercased()) · \(analytics.provenance.scope.replacingOccurrences(of: "_", with: " ")) scope")
                        .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                }
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading analytics...").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let loadError {
                    LifecycleCard(accentDanger: true) { Text(loadError).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let analytics {
                    hero(analytics)
                    Text("TOP RESPONDENTS · CLAIM COUNT").font(EType.micro).foregroundStyle(palette.textTertiary)
                    carriers(analytics)
                    Text("BY CLAIM TYPE · COUNT AND VALUE").font(EType.micro).foregroundStyle(palette.textTertiary)
                    types(analytics)
                    provenance(analytics)
                    HStack(spacing: 8) {
                        CTAButton(title: "Refresh", action: { Task { await load() } }, trailingIcon: "arrow.clockwise")
                        secondaryButton811(title: "Compare") {}
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
            Text("VESSEL OPERATOR · CLAIMS ANALYTICS").font(.system(size: 9, weight: .heavy))
                .tracking(1).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("OCEAN").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
        }
    }

    private func hero(_ value: Analytics811) -> some View {
        RimCard811 {
            VStack(alignment: .leading, spacing: 10) {
                Text("PAID CLAIM STATUS / ALL SCOPED CLAIMS").font(EType.micro).foregroundStyle(palette.textTertiary)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(percent(value.recoveryRate, truth: value.metricStates.recoveryRate))
                            .font(.system(size: 40, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Text(caption(value.metricStates.recoveryRate)).font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary).lineLimit(3)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(count(value.frequency, truth: value.metricStates.frequency))
                            .font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        Text("claims").font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        Text(duration(value.avgResolutionDays, truth: value.metricStates.avgResolutionDays))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(caption(value.metricStates.avgResolutionDays)).font(.system(size: 9))
                            .foregroundStyle(palette.textTertiary).multilineTextAlignment(.trailing).lineLimit(3)
                    }.frame(maxWidth: 150, alignment: .trailing)
                }
                Divider().overlay(palette.borderFaint)
                Text("Average claim value · \(averageCost(value))")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
                Text(caption(value.metricStates.avgCost)).font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func carriers(_ value: Analytics811) -> some View {
        if value.topCarriers.isEmpty {
            EusoEmptyState(systemImage: "chart.bar", title: "No respondent observations",
                           subtitle: "Carrier rows appear when claims have a respondent company.")
        } else {
            LifecycleCard {
                VStack(spacing: 0) {
                    let denominator = value.topCarriers.compactMap { row -> Int? in
                        guard let truth = row.metricStates?.claimCount,
                              metricUnavailableLabel(truth) == nil else { return nil }
                        return row.claimCount
                    }.max()
                    ForEach(Array(value.topCarriers.enumerated()), id: \.element.carrier) { index, row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.carrier).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                                    Text("\(count(row.claimCount, truth: row.metricStates?.claimCount)) claims · claim-count ranking")
                                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                                }
                                Spacer()
                                Text(money(row.totalValue, currency: row.currency,
                                           buckets: row.totalsByCurrency, truth: row.metricState))
                                    .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                                    .multilineTextAlignment(.trailing)
                            }
                            GeometryReader { geometry in
                                Capsule().fill(palette.borderFaint)
                                    .overlay(alignment: .leading) {
                                        if let truth = row.metricStates?.claimCount,
                                           metricUnavailableLabel(truth) == nil,
                                           let denominator, denominator > 0 {
                                            Capsule().fill(Brand.blue)
                                                .frame(width: geometry.size.width * Double(row.claimCount) / Double(denominator))
                                        }
                                    }
                            }.frame(height: 7)
                            Text(caption(row.metricState)).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
                        }.padding(.vertical, 10)
                        if index < value.topCarriers.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func types(_ value: Analytics811) -> some View {
        if value.byType.isEmpty {
            EusoEmptyState(systemImage: "chart.pie", title: "No type observations",
                           subtitle: caption(value.metricStates.frequency))
        } else {
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(Array(value.byType.enumerated()), id: \.element.type) { index, row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.type.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text("\(count(row.count, truth: row.metricStates?.count)) claims").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Text(money(row.value, currency: row.currency,
                                       buckets: row.totalsByCurrency, truth: row.metricState))
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                                .multilineTextAlignment(.trailing)
                        }.padding(.vertical, 10)
                        if index < value.byType.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private func provenance(_ value: Analytics811) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOURCE · \(value.provenance.source)").font(EType.micro).foregroundStyle(palette.textTertiary)
            Text("Snapshot calculated \(value.provenance.computedAt)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Mode scope · \((value.transportMode ?? value.provenance.transportMode ?? "unknown").uppercased())")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            if let unavailable = metricUnavailableLabel(value.metricStates.unvaluedCount) {
                Text("Unvalued claim coverage · \(unavailable)")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            } else if value.unvaluedCount > 0 {
                Text("Partial money coverage: \(value.unvaluedCount) records lack amount or ISO currency.")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func count(_ value: Int, truth: MetricTruth811) -> String {
        metricUnavailableLabel(truth) ?? "\(value)"
    }

    private func count(_ value: Int, truth: MetricTruth811?) -> String {
        guard let truth else { return "Access unknown" }
        return count(value, truth: truth)
    }

    private func percent(_ value: Double?, truth: MetricTruth811) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value else { return "Unavailable" }
        return String(format: "%.1f%%", value * 100)
    }

    private func duration(_ value: Double?, truth: MetricTruth811) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value else { return "Unavailable" }
        return String(format: "%.1f d", value)
    }

    private func averageCost(_ value: Analytics811) -> String {
        let truth = value.metricStates.avgCost
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        if !value.avgCostByCurrency.isEmpty {
            return value.avgCostByCurrency.map { formatted($0.amount, currency: $0.currency) }.joined(separator: " · ")
        }
        guard let amount = value.avgCost, let currency = value.avgCostCurrency else { return "Unavailable" }
        return formatted(amount, currency: currency)
    }

    private func money(_ value: Double?, currency: String?, buckets: [MoneyBucket811], truth: MetricTruth811) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        if !buckets.isEmpty { return buckets.map { formatted($0.amount, currency: $0.currency) }.joined(separator: " · ") }
        guard let value, let currency else { return "Unavailable" }
        return formatted(value, currency: currency)
    }

    private func formatted(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.0f", amount))"
    }

    private func caption(_ truth: MetricTruth811) -> String {
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

    private func metricUnavailableLabel(_ truth: MetricTruth811) -> String? {
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

    private func metricUnavailableLabel(_ truth: MetricTruth811?) -> String? {
        guard let truth else { return "Access unknown" }
        return metricUnavailableLabel(truth)
    }

    private func load() async {
        loading = true
        loadError = nil
        struct Input: Encodable { let transportMode: String; let period: String }
        do {
            analytics = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimsAnalytics",
                input: Input(transportMode: "VESSEL", period: "year")
            )
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func secondaryButton811(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44).background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }
}

private struct RimCard811<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

#Preview("811 · Claims Analytics · Night") {
    VesselClaimsAnalyticsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("811 · Claims Analytics · Light") {
    VesselClaimsAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
