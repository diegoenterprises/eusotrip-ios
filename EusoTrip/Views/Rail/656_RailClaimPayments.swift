//
//  656_RailClaimPayments.swift
//  EusoTrip - Rail Engineer - Claim Payments.
//
//  Payment totals are rendered from mode-scoped ISO currency buckets with
//  explicit metric state, page scope, and source/calculation timestamps.
//

import SwiftUI
import UIKit

private struct ClaimPaymentsInput656: Encodable { let transportMode: String; let limit: Int; let offset: Int }

private struct ClaimPayment656: Decodable, Identifiable {
    let id: String
    let claimId: String
    let claimNumber: String
    let amount: Double
    let currency: String
    let status: String
    let method: String?
    let scheduledDate: String?
    let paidDate: String?
    let reference: String
    let transportMode: String?
    let transactionReference: String?
}

private struct PaymentCurrencyBucket656: Decodable {
    let currency: String
    let paid: Double
    let pending: Double
    let count: Int
}

private struct ClaimPaymentsResp656: Decodable {
    let payments: [ClaimPayment656]
    let total: Int
    let totalPaid: Double?
    let totalPending: Double?
    let totalCurrency: String?
    let totalsByCurrency: [PaymentCurrencyBucket656]
    let transportMode: String?
    let metricStates: ClaimPaymentMetricStates656
    let pageScope: ClaimPaymentPageScope656
    let provenance: ClaimPaymentProvenance656
}

private struct ClaimPaymentMetricStates656: Decodable {
    let total: FreightClaimsAPI.MetricTruth
    let totalPaid: FreightClaimsAPI.MetricTruth
    let totalPending: FreightClaimsAPI.MetricTruth
}

private struct ClaimPaymentPageScope656: Decodable {
    let offset: Int
    let limit: Int
    let returnedCount: Int
    let totalMatching: Int
    let status: String?
    let transportMode: String?
}

private struct ClaimPaymentProvenance656: Decodable {
    let observedAt: String?
    let computedAt: String
    let transportMode: String?
}

private struct ProcessClaimPaymentInput656: Encodable {
    let claimId: String
    let amount: Double
    let method: String
    let reference: String?
    let notes: String?
}
private struct ProcessClaimPaymentResp656: Decodable { let success: Bool; let paymentId: String?; let status: String? }

private struct ClaimReportInput656: Encodable {
    let claimId: String
    let format: String
    let includeEvidence: Bool
    let includeTimeline: Bool
    let includeFinancials: Bool
    let purpose: String
}
private struct ClaimReportResp656: Decodable { let success: Bool; let filename: String?; let content: String? }

private struct AgingBar656: Identifiable {
    let id = UUID()
    let label: String
    let fraction: CGFloat
    let count: Int
    let tint: Color
}

struct RailClaimPaymentsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailClaimPaymentsBody656() } nav: {
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

private struct RailClaimPaymentsBody656: View {
    @Environment(\.palette) private var palette
    @State private var response: ClaimPaymentsResp656?
    @State private var loading = true
    @State private var loadError: String?

    private var aging: [AgingBar656] {
        guard let response else { return [] }
        var counts = [0, 0, 0, 0]
        for payment in response.payments {
            guard let days = ageDays(payment.scheduledDate) else { continue }
            switch days {
            case ..<31: counts[0] += 1
            case 31..<61: counts[1] += 1
            case 61..<91: counts[2] += 1
            default: counts[3] += 1
            }
        }
        guard let maximum = counts.max(), maximum > 0 else { return [] }
        let labels = ["0-30", "31-60", "61-90", "90+"]
        let colors = [Brand.blue, Brand.warning, Brand.magenta, Brand.danger]
        return counts.indices.map {
            AgingBar656(label: labels[$0], fraction: CGFloat(counts[$0]) / CGFloat(maximum),
                        count: counts[$0], tint: colors[$0])
        }
    }

    private var missingScheduleCount: Int {
        guard let response else { return 0 }
        return response.payments.filter { ageDays($0.scheduledDate) == nil }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                if loading {
                    LifecycleCard { Text("Loading payments...").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let loadError {
                    LifecycleCard(accentDanger: true) { Text(loadError).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let response {
                    hero(response)
                    paymentList(response)
                    contractBand(response)
                    actions(response)
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
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · CLAIM PAYMENTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("RECON · BNSF").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Payments").font(.system(size: 28, weight: .heavy)).foregroundStyle(palette.textPrimary)
            IridescentHairline()
        }
    }

    private func hero(_ value: ClaimPaymentsResp656) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PENDING BY ISO CURRENCY").font(EType.micro).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(metricCount(value.total, truth: value.metricStates.total)) payments")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            Text(bucketMoney(value.totalsByCurrency, keyPath: \.pending, truth: value.metricStates.totalPending))
                .font(.system(size: 25, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                .fixedSize(horizontal: false, vertical: true)
            if aging.isEmpty {
                Text("Payment aging unavailable: no scheduled dates are present on this page.")
                    .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(aging) { bucket in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4).fill(bucket.tint).frame(height: 8 + 24 * bucket.fraction)
                            Text("\(bucket.label) · \(bucket.count)").font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.textTertiary)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 48)
            }
        }
        .padding(18).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func paymentList(_ value: ClaimPaymentsResp656) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECONCILE · CLAIM PAYMENTS").font(EType.micro).foregroundStyle(palette.textTertiary)
            if value.payments.isEmpty {
                EusoEmptyState(systemImage: "checklist", title: "No payment rows returned",
                               subtitle: "No claim-payment rows are present on the current page.")
            } else {
                LifecycleCard {
                    VStack(spacing: 0) {
                        ForEach(Array(value.payments.prefix(8).enumerated()), id: \.element.id) { index, payment in
                            paymentRow(payment)
                            if index < min(value.payments.count, 8) - 1 { Divider().overlay(palette.borderFaint) }
                        }
                    }
                }
            }
        }
    }

    private func paymentRow(_ payment: ClaimPayment656) -> some View {
        let info = statusInfo(payment.status)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(info.tint.opacity(0.16)).frame(width: 40, height: 40)
                .overlay(Image(systemName: info.icon).foregroundStyle(info.tint))
            VStack(alignment: .leading, spacing: 3) {
                Text(payment.claimNumber).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(payment.reference) · \(payment.method ?? "method unavailable") · \(payment.transportMode ?? "mode unavailable")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: info.label, kind: info.kind)
                Text(money(payment.amount, currency: payment.currency)).font(.system(size: 13, weight: .bold))
                    .monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }.padding(.vertical, 10)
    }

    private func contractBand(_ value: ClaimPaymentsResp656) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PAID BY ISO CURRENCY · \(bucketMoney(value.totalsByCurrency, keyPath: \.paid, truth: value.metricStates.totalPaid))")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("Current page: \(value.pageScope.returnedCount) rows · total matching rail ledger: \(value.pageScope.totalMatching)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("\(truthLabel(value.metricStates.total)) · source \(timestampLabel(value.provenance.observedAt)) · calculated \(timestampLabel(value.provenance.computedAt))")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Amounts remain separated by ISO currency; no FX conversion is applied.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            if missingScheduleCount > 0 {
                Text("\(missingScheduleCount) current-page payments have no scheduled date and are excluded from aging.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func actions(_ value: ClaimPaymentsResp656) -> some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Reconcile", action: { Task { await reconcileNextPayment(value) } })
                .disabled(nextPendingPayment(value) == nil).opacity(nextPendingPayment(value) == nil ? 0.45 : 1)
            Button { Task { await exportClaimReport(value) } } label: {
                Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            }.buttonStyle(.plain).disabled(value.payments.first == nil)
        }
    }

    private func ageDays(_ iso: String?) -> Int? {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return max(0, Int(Date().timeIntervalSince(date) / 86_400))
    }

    private func money(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.0f", amount))"
    }

    private func bucketMoney(
        _ buckets: [PaymentCurrencyBucket656],
        keyPath: KeyPath<PaymentCurrencyBucket656, Double>,
        truth: FreightClaimsAPI.MetricTruth
    ) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return unavailable }
        guard !buckets.isEmpty else { return "No observations" }
        return buckets.map { money($0[keyPath: keyPath], currency: $0.currency) }.joined(separator: " · ")
    }

    private func truthLabel(_ truth: FreightClaimsAPI.MetricTruth) -> String {
        if let unavailable = metricUnavailableLabel(truth) { return truth.reason ?? unavailable }
        switch truth.valueState {
        case .measured: return "Measured"
        case .measuredByDimension: return "Measured by currency"
        case .partial: return "Partial"
        case .noObservations: return "No observations"
        case .notModeled: return "Not modeled"
        }
    }

    private func metricCount(_ value: Int, truth: FreightClaimsAPI.MetricTruth) -> String {
        metricUnavailableLabel(truth) ?? value.formatted()
    }

    private func metricUnavailableLabel(_ truth: FreightClaimsAPI.MetricTruth) -> String? {
        guard truth.accessState == .granted else {
            return truth.accessState == .restricted ? "Restricted" : "Access unknown"
        }
        guard truth.trackingState == .tracked else { return "Not tracked" }
        switch truth.valueState {
        case .notModeled: return "Not modeled"
        case .noObservations: return "No observations"
        case .measured, .measuredByDimension, .partial: return nil
        }
    }

    private func timestampLabel(_ value: String?) -> String {
        guard let value, let date = ISO8601DateFormatter().date(from: value) else { return "not observed" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func statusInfo(_ status: String) -> (icon: String, tint: Color, label: String, kind: StatusPill.Kind) {
        switch status.lowercased() {
        case "paid": return ("checkmark.circle", Brand.success, "PAID", .success)
        case "processing": return ("clock", Brand.warning, "PROCESSING", .warning)
        case "failed": return ("exclamationmark.triangle", Brand.danger, "FAILED", .danger)
        case "pending": return ("clock", Brand.warning, "PENDING", .warning)
        default: return ("circle", Brand.info, status.uppercased(), .info)
        }
    }

    private func nextPendingPayment(_ value: ClaimPaymentsResp656) -> ClaimPayment656? {
        value.payments.first { $0.status.lowercased() == "pending" && !$0.claimId.isEmpty && $0.amount > 0 }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            response = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimPayments", input: ClaimPaymentsInput656(transportMode: "RAIL", limit: 20, offset: 0)
            )
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func reconcileNextPayment(_ value: ClaimPaymentsResp656) async {
        guard let payment = nextPendingPayment(value) else { return }
        do {
            let _: ProcessClaimPaymentResp656 = try await EusoTripAPI.shared.mutation(
                "freightClaims.processClaimPayment",
                input: ProcessClaimPaymentInput656(claimId: payment.claimId, amount: payment.amount,
                                                   method: "ach", reference: payment.reference,
                                                   notes: "Rail claim reconciliation release")
            )
            await load()
        } catch {
            loadError = error.eusoUserCopy
        }
    }

    private func exportClaimReport(_ value: ClaimPaymentsResp656) async {
        guard let claimId = value.payments.first?.claimId else { return }
        do {
            let report: ClaimReportResp656 = try await EusoTripAPI.shared.mutation(
                "freightClaims.generateClaimReport",
                input: ClaimReportInput656(claimId: claimId, format: "csv", includeEvidence: true,
                                           includeTimeline: true, includeFinancials: true, purpose: "internal")
            )
            if let content = report.content, !content.isEmpty { UIPasteboard.general.string = content }
        } catch {
            loadError = error.eusoUserCopy
        }
    }
}

#Preview("656 · Rail Claim Payments · Night") {
    RailClaimPaymentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("656 · Rail Claim Payments · Light") {
    RailClaimPaymentsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
