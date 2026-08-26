//
//  670_RailShortageClaims.swift
//  EusoTrip - Rail Engineer - Shortage Claims.
//
//  The response is explicitly page scoped. Quantity and money values retain
//  their units, ISO currencies, and metricStates without client substitution.
//

import SwiftUI

private struct MetricTruth670: Decodable {
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
private struct MoneyBucket670: Decodable { let currency: String; let amount: Double }
private struct QuantityReading670 {
    let unit: String?
    let value: Double?
    let truth: MetricTruth670
}
private struct ShortageClaimsInput670: Encodable { let transportMode: String; let limit: Int; let offset: Int }

private struct ShortageClaimsResp670: Decodable {
    struct Claim: Decodable, Identifiable {
        struct Reconciliation: Decodable {
            let bolQty: Double?
            let deliveryReceiptQty: Double?
            let variance: Double?
            let variancePercent: Double?
        }
        struct States: Decodable {
            let expectedQty: MetricTruth670
            let receivedQty: MetricTruth670
            let shortageQty: MetricTruth670
            let shortageValue: MetricTruth670
        }
        let id: String
        let claimNumber: String
        let referenceNumber: String?
        let transportMode: String?
        let commodity: String?
        let quantityUnit: String?
        let expectedQty: Double?
        let receivedQty: Double?
        let shortageQty: Double?
        let shortageValue: Double?
        let currency: String?
        let status: String?
        let filedDate: String
        let reconciliation: Reconciliation
        let metricStates: States
    }
    struct Summary: Decodable {
        struct Scope: Decodable { let kind: String; let offset: Int; let limit: Int; let returnedCount: Int }
        struct States: Decodable {
            let totalMatchingClaims: MetricTruth670?
            let totalShortages: MetricTruth670
            let totalValue: MetricTruth670
            let unvaluedCount: MetricTruth670?
            let unreconciledCount: MetricTruth670?
            let avgShortagePercent: MetricTruth670
        }
        let totalShortages: Int
        let totalMatchingClaims: Int
        let scope: Scope
        let totalValue: Double?
        let totalValueCurrency: String?
        let totalsByCurrency: [MoneyBucket670]
        let unvaluedCount: Int
        let avgShortagePercent: Double?
        let unreconciledCount: Int
        let topCommodities: [String]
        let metricStates: States
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
    let claims: [Claim]
    let total: Int
    let summary: Summary
    let provenance: Provenance
}

struct RailShortageClaimsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailShortageClaimsBody670() } nav: {
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

private struct RailShortageClaimsBody670: View {
    @Environment(\.palette) private var palette
    @State private var response: ShortageClaimsResp670?
    @State private var loading = true
    @State private var loadError: String?

    private let receivedColor = Color(red: 0.129, green: 0.588, blue: 0.953)
    private let shortageColor = Color(red: 0.937, green: 0.325, blue: 0.314)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if loading {
                    LifecycleCard { Text("Loading shortage claims...").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let loadError {
                    LifecycleCard(accentDanger: true) { Text(loadError).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let response {
                    if response.claims.isEmpty {
                        EusoEmptyState(systemImage: "shippingbox", title: emptyTitle(response), subtitle: emptySubtitle(response))
                    } else {
                        hero(response)
                        claimsCard(response)
                    }
                    contractBand(response)
                    CTAButton(title: "Refresh reconciliation", action: { Task { await load() } }, trailingIcon: "arrow.clockwise")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · CARGO CLAIMS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("SHORTAGE").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Shortage claims").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("BOL versus received · values remain page scoped and dimensioned")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            IridescentHairline()
        }
    }

    private func hero(_ value: ShortageClaimsResp670) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CURRENT PAGE SHORTAGE VALUE").font(EType.micro).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(metricCount(value.summary.scope.returnedCount, truth: value.summary.metricStates.totalShortages)) on page · \(metricCount(value.summary.totalMatchingClaims, truth: value.summary.metricStates.totalMatchingClaims)) matching")
                        .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Text(money(value.summary.totalValue, currency: value.summary.totalValueCurrency,
                           buckets: value.summary.totalsByCurrency, truth: value.summary.metricStates.totalValue))
                    .font(.system(size: 28, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption(value.summary.metricStates.totalValue)).font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary).lineLimit(3)
                HStack(alignment: .top) {
                    quantitySummary("EXPECTED", readings: value.claims.map { claim in
                        QuantityReading670(unit: claim.quantityUnit, value: claim.expectedQty, truth: claim.metricStates.expectedQty)
                    })
                    quantitySummary("RECEIVED", readings: value.claims.map { claim in
                        QuantityReading670(unit: claim.quantityUnit, value: claim.receivedQty, truth: claim.metricStates.receivedQty)
                    })
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AVG SHORTAGE").font(EType.micro).foregroundStyle(palette.textTertiary)
                        Text(percent(value.summary.avgShortagePercent, truth: value.summary.metricStates.avgShortagePercent))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(caption(value.summary.metricStates.avgShortagePercent)).font(.system(size: 9))
                            .foregroundStyle(palette.textTertiary).lineLimit(3)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func quantitySummary(_ label: String, readings: [QuantityReading670]) -> some View {
        let unavailableStates = readings.compactMap { metricUnavailableLabel($0.truth) }
        let completeReadings = readings.compactMap { reading -> (String, Double)? in
            guard let unit = reading.unit, let value = reading.value else { return nil }
            return (unit, value)
        }
        let grouped = Dictionary(grouping: completeReadings, by: \.0).mapValues { $0.reduce(0) { $0 + $1.1 } }
        let text: String
        if readings.isEmpty {
            text = "No observations"
        } else if !unavailableStates.isEmpty {
            text = Set(unavailableStates).count == 1 ? unavailableStates[0] : "Mixed availability"
        } else if completeReadings.count != readings.count {
            text = "Unavailable"
        } else {
            text = grouped.keys.sorted().map { "\(quantity(grouped[$0]!)) \($0)" }.joined(separator: " · ")
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(label).font(EType.micro).foregroundStyle(palette.textTertiary)
            Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func claimsCard(_ value: ShortageClaimsResp670) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CLAIMS · CURRENT PAGE").font(EType.micro).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("offset \(value.summary.scope.offset) · limit \(value.summary.scope.limit)")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(Array(value.claims.enumerated()), id: \.element.id) { index, claim in
                        claimRow(claim)
                        if index < value.claims.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private func claimRow(_ claim: ShortageClaimsResp670.Claim) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(statusColor(claim.status).opacity(0.14)).frame(width: 40, height: 40)
                .overlay(Image(systemName: "shippingbox").foregroundStyle(statusColor(claim.status)))
            VStack(alignment: .leading, spacing: 5) {
                Text(claim.commodity ?? "Commodity unavailable").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(claim.claimNumber) · \(claim.referenceNumber ?? "reference unavailable") · \(claim.transportMode ?? "mode unavailable")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
                Text("Expected \(quantity(claim.expectedQty, unit: claim.quantityUnit, truth: claim.metricStates.expectedQty)) · received \(quantity(claim.receivedQty, unit: claim.quantityUnit, truth: claim.metricStates.receivedQty))")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                if let fraction = receivedFraction(claim) {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            Capsule().fill(receivedColor).frame(width: geometry.size.width * fraction)
                            Capsule().fill(shortageColor).frame(width: geometry.size.width * (1 - fraction))
                        }
                    }.frame(height: 8)
                }
                Text("Shortage \(quantity(claim.shortageQty, unit: claim.quantityUnit, truth: claim.metricStates.shortageQty))")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(shortageColor)
                Text(caption(claim.metricStates.shortageQty)).font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(money(claim.shortageValue, currency: claim.currency, buckets: [], truth: claim.metricStates.shortageValue))
                    .font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.trailing)
                Text((claim.status ?? "STATUS UNAVAILABLE").replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(EType.micro).foregroundStyle(statusColor(claim.status))
                Text("filed \(claim.filedDate)").font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }.frame(maxWidth: 120, alignment: .trailing)
        }.padding(.vertical, 10)
    }

    private func contractBand(_ value: ShortageClaimsResp670) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SCOPE · CURRENT PAGE").font(EType.micro).foregroundStyle(palette.textTertiary)
            Text("\(metricCount(value.summary.totalShortages, truth: value.summary.metricStates.totalShortages)) returned · \(metricCount(value.total, truth: value.summary.metricStates.totalMatchingClaims)) total matching claims")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Snapshot calculated \(value.provenance.computedAt) from \(value.provenance.source)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Mode scope · \((value.transportMode ?? value.provenance.transportMode ?? "unknown").uppercased())")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            if let unavailable = metricUnavailableLabel(value.summary.metricStates.unvaluedCount) {
                Text("Unvalued claim coverage · \(unavailable)")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            } else if value.summary.unvaluedCount > 0 {
                Text("\(value.summary.unvaluedCount) page rows lack a usable amount or ISO currency.")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            }
            if let unavailable = metricUnavailableLabel(value.summary.metricStates.unreconciledCount) {
                Text("Quantity reconciliation coverage · \(unavailable)")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            } else if value.summary.unreconciledCount > 0 {
                Text("\(value.summary.unreconciledCount) page rows lack expected or received quantity evidence.")
                    .font(.system(size: 10)).foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    private func receivedFraction(_ claim: ShortageClaimsResp670.Claim) -> CGFloat? {
        guard claim.metricStates.expectedQty.valueState == "measured",
              claim.metricStates.receivedQty.valueState == "measured",
              metricUnavailableLabel(claim.metricStates.expectedQty) == nil,
              metricUnavailableLabel(claim.metricStates.receivedQty) == nil,
              let expected = claim.expectedQty, expected > 0, let received = claim.receivedQty else { return nil }
        return min(1, max(0, CGFloat(received / expected)))
    }

    private func quantity(_ value: Double?, unit: String?, truth: MetricTruth670) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value, let unit else { return "Unavailable" }
        return "\(quantity(value)) \(unit)"
    }

    private func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func percent(_ value: Double?, truth: MetricTruth670) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard let value else { return "Unavailable" }
        return String(format: "%.1f%%", value)
    }

    private func money(_ value: Double?, currency: String?, buckets: [MoneyBucket670], truth: MetricTruth670) -> String {
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

    private func caption(_ truth: MetricTruth670) -> String {
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

    private func metricUnavailableLabel(_ truth: MetricTruth670) -> String? {
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

    private func metricUnavailableLabel(_ truth: MetricTruth670?) -> String? {
        guard let truth else { return "Access unknown" }
        return metricUnavailableLabel(truth)
    }

    private func metricCount(_ value: Int, truth: MetricTruth670) -> String {
        metricUnavailableLabel(truth) ?? "\(value)"
    }

    private func metricCount(_ value: Int, truth: MetricTruth670?) -> String {
        guard let truth else { return "Access unknown" }
        return metricCount(value, truth: truth)
    }

    private func statusColor(_ status: String?) -> Color {
        switch status?.lowercased() {
        case "paid", "closed", "settled", "approved": return Brand.success
        case "denied": return Brand.danger
        case "investigating", "under_review", "pending_evidence": return Brand.warning
        default: return Brand.info
        }
    }

    private func emptyTitle(_ value: ShortageClaimsResp670) -> String {
        guard let truth = value.summary.metricStates.totalMatchingClaims else {
            return "Claim availability unknown"
        }
        guard truth.accessState == "granted", truth.trackingState == "tracked" else {
            return "Claim availability unknown"
        }
        if truth.valueState == "no_observations" { return "No matching shortage observations" }
        if truth.valueState == "not_modeled" { return "Claim availability unknown" }
        return value.summary.totalMatchingClaims > 0 ? "No claims on this page" : "No matching shortage observations"
    }

    private func emptySubtitle(_ value: ShortageClaimsResp670) -> String {
        guard let truth = value.summary.metricStates.totalMatchingClaims else {
            return "The matching-claim count has no access or tracking state."
        }
        if truth.valueState == "no_observations",
           truth.accessState == "granted",
           truth.trackingState == "tracked" {
            return caption(value.summary.metricStates.totalShortages)
        }
        if let unavailable = metricUnavailableLabel(truth) {
            return "The matching-claim count is \(unavailable.lowercased())."
        }
        return value.summary.totalMatchingClaims > 0
            ? "This page has no claims. \(value.summary.totalMatchingClaims) claims still match the selected scope."
            : caption(value.summary.metricStates.totalShortages)
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            response = try await EusoTripAPI.shared.query(
                "freightClaims.getShortageClaims",
                input: ShortageClaimsInput670(transportMode: "RAIL", limit: 20, offset: 0)
            )
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

#Preview("670 · Shortage claims · Light") {
    RailShortageClaimsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("670 · Shortage claims · Night") {
    RailShortageClaimsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
