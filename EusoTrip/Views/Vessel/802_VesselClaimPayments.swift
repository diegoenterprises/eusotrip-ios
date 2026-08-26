//
//  802_VesselClaimPayments.swift
//  EusoTrip - Vessel Operator - Claim Payments.
//
//  All amounts retain their ISO currency. Method shares use payment counts, so
//  mixed-currency ledgers are never summed into a synthetic scalar.
//

import SwiftUI
import UIKit

private struct ClaimPaymentsInput802: Encodable { let transportMode: String; let limit: Int; let offset: Int }
private struct ClaimPayment802: Decodable, Identifiable {
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
private struct PaymentCurrencyBucket802: Decodable {
    let currency: String
    let paid: Double
    let pending: Double
    let count: Int
}
private struct ClaimPaymentsResp802: Decodable {
    let payments: [ClaimPayment802]
    let total: Int
    let totalPaid: Double?
    let totalPending: Double?
    let totalCurrency: String?
    let totalsByCurrency: [PaymentCurrencyBucket802]
    let transportMode: String?
    let metricStates: ClaimPaymentMetricStates802
    let pageScope: ClaimPaymentPageScope802
    let provenance: ClaimPaymentProvenance802
}
private struct ClaimPaymentMetricStates802: Decodable {
    let total: FreightClaimsAPI.MetricTruth
    let totalPaid: FreightClaimsAPI.MetricTruth
    let totalPending: FreightClaimsAPI.MetricTruth
}
private struct ClaimPaymentPageScope802: Decodable {
    let offset: Int; let limit: Int; let returnedCount: Int; let totalMatching: Int
    let status: String?; let transportMode: String?
}
private struct ClaimPaymentProvenance802: Decodable {
    let observedAt: String?; let computedAt: String; let transportMode: String?
}
private struct ProcessClaimPaymentInput802: Encodable {
    let claimId: String; let amount: Double; let method: String; let reference: String?; let notes: String?
}
private struct ProcessClaimPaymentResp802: Decodable { let success: Bool; let paymentId: String?; let status: String? }
private struct ClaimReportInput802: Encodable {
    let claimId: String; let format: String; let includeEvidence: Bool
    let includeTimeline: Bool; let includeFinancials: Bool; let purpose: String
}
private struct ClaimReportResp802: Decodable { let success: Bool; let filename: String?; let content: String? }

private struct MethodRow802: Identifiable {
    let id: String
    let method: String
    let currency: String
    let count: Int
    let amount: Double
    let countShare: Double
    let color: Color
}

struct VesselClaimPaymentsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselClaimPaymentsBody() } nav: {
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

private struct VesselClaimPaymentsBody: View {
    @Environment(\.palette) private var palette
    @State private var response: ClaimPaymentsResp802?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Claim payments").font(.system(size: 30, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Recoveries and disbursements by ISO currency").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading payments...").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let loadError {
                    LifecycleCard(accentDanger: true) { Text(loadError).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let response {
                    hero(response)
                    Text("BY METHOD AND CURRENCY · PAYMENT COUNT SHARE").font(EType.micro).foregroundStyle(palette.textTertiary)
                    methodCard(response)
                    Text("RECENT REMITTANCES · CURRENT PAGE").font(EType.micro).foregroundStyle(palette.textTertiary)
                    remittances(response)
                    contractBand(response)
                    actionRow(response)
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
            Text("VESSEL OPERATOR · CLAIM PAYMENTS").font(.system(size: 9, weight: .heavy))
                .tracking(1).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("ISO").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
        }
    }

    private func hero(_ value: ClaimPaymentsResp802) -> some View {
        RimCard802 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RECOVERY LEDGER").font(EType.micro).foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(metricCount(value.total, truth: value.metricStates.total)) payments")
                        .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Text("Paid · \(bucketMoney(value.totalsByCurrency, keyPath: \.paid, truth: value.metricStates.totalPaid))")
                    .font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Pending · \(bucketMoney(value.totalsByCurrency, keyPath: \.pending, truth: value.metricStates.totalPending))")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(methodRows(value)) { row in
                            RoundedRectangle(cornerRadius: 4).fill(row.color)
                                .frame(width: max(2, geometry.size.width * row.countShare - 2))
                        }
                        Spacer(minLength: 0)
                    }.background(RoundedRectangle(cornerRadius: 4).fill(palette.borderFaint))
                }.frame(height: 8)
            }
        }
    }

    @ViewBuilder
    private func methodCard(_ value: ClaimPaymentsResp802) -> some View {
        let rows = methodRows(value)
        if rows.isEmpty {
            EusoEmptyState(systemImage: "tray", title: "No payment rows returned",
                           subtitle: "Method and currency rows appear as claim payments post.")
        } else {
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 10) {
                            Circle().fill(row.color).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(methodName(row.method)).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text("\(row.count) payments · \(Int((row.countShare * 100).rounded()))% of page rows")
                                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            Text(money(row.amount, currency: row.currency)).font(.system(size: 12, weight: .bold))
                                .monospacedDigit().foregroundStyle(palette.textPrimary)
                        }.padding(.vertical, 10)
                        if index < rows.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func remittances(_ value: ClaimPaymentsResp802) -> some View {
        if value.payments.isEmpty {
            Text("No remittances on the current page.").font(EType.caption).foregroundStyle(palette.textTertiary)
        } else {
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(Array(value.payments.prefix(4).enumerated()), id: \.element.id) { index, payment in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(payment.claimNumber).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text("\(payment.status) · \(payment.reference) · \(payment.transportMode ?? "mode unavailable")").font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(palette.textTertiary).lineLimit(1)
                            }
                            Spacer()
                            Text(money(payment.amount, currency: payment.currency)).font(.system(size: 12, weight: .bold))
                                .monospacedDigit().foregroundStyle(palette.textPrimary)
                        }.padding(.vertical, 10)
                        if index < min(value.payments.count, 4) - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private func contractBand(_ value: ClaimPaymentsResp802) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current page: \(value.pageScope.returnedCount) rows · total matching vessel ledger: \(value.pageScope.totalMatching)")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("\(truthLabel(value.metricStates.total)) · source \(timestampLabel(value.provenance.observedAt)) · calculated \(timestampLabel(value.provenance.computedAt))")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text("Amounts remain separated by ISO currency; no FX conversion is applied.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func actionRow(_ value: ClaimPaymentsResp802) -> some View {
        HStack(spacing: 8) {
            CTAButton(title: "Release pending", action: { Task { await releasePending(value) } }, trailingIcon: "arrow.right")
                .disabled(nextPendingPayment(value) == nil).opacity(nextPendingPayment(value) == nil ? 0.45 : 1)
            secondaryButton802(title: "Export") { Task { await exportStatement(value) } }
        }
    }

    private func methodRows(_ value: ClaimPaymentsResp802) -> [MethodRow802] {
        guard !value.payments.isEmpty else { return [] }
        struct Bucket { var count: Int; var amount: Double }
        var buckets: [String: Bucket] = [:]
        for payment in value.payments {
            let method = payment.method?.lowercased() ?? "method_unavailable"
            let key = "\(method)|\(payment.currency)"
            if var bucket = buckets[key] {
                bucket.count += 1
                bucket.amount += payment.amount
                buckets[key] = bucket
            } else {
                buckets[key] = Bucket(count: 1, amount: payment.amount)
            }
        }
        return buckets.map { key, bucket in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            let method = parts.first ?? "method_unavailable"
            let currency = parts.count == 2 ? parts[1] : "currency unavailable"
            return MethodRow802(id: key, method: method, currency: currency, count: bucket.count,
                                amount: bucket.amount, countShare: Double(bucket.count) / Double(value.payments.count),
                                color: methodColor(method))
        }.sorted { $0.count > $1.count }
    }

    private func money(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currency) \(String(format: "%.0f", amount))"
    }

    private func bucketMoney(
        _ buckets: [PaymentCurrencyBucket802],
        keyPath: KeyPath<PaymentCurrencyBucket802, Double>,
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

    private func methodName(_ value: String) -> String {
        switch value {
        case "ach": return "ACH transfer"
        case "wire": return "Wire"
        case "check": return "Check"
        case "deduct_from_settlement": return "Settlement deduction"
        case "credit": return "Credit memo"
        case "method_unavailable": return "Method unavailable"
        default: return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func methodColor(_ value: String) -> Color {
        switch value {
        case "ach": return Brand.blue
        case "wire": return Brand.magenta
        case "deduct_from_settlement": return Brand.success
        case "credit": return Brand.warning
        default: return Brand.info
        }
    }

    private func nextPendingPayment(_ value: ClaimPaymentsResp802) -> ClaimPayment802? {
        value.payments.first { $0.status.lowercased() == "pending" && !$0.claimId.isEmpty && $0.amount > 0 }
    }

    private func releaseMethod(_ method: String?) -> String {
        guard let method = method?.lowercased(),
              ["euso_wallet", "ach", "check", "wire", "deduct_from_settlement", "credit"].contains(method)
        else { return "ach" }
        return method
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            response = try await EusoTripAPI.shared.query(
                "freightClaims.getClaimPayments", input: ClaimPaymentsInput802(transportMode: "VESSEL", limit: 20, offset: 0)
            )
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    private func releasePending(_ value: ClaimPaymentsResp802) async {
        guard let payment = nextPendingPayment(value) else { return }
        do {
            let _: ProcessClaimPaymentResp802 = try await EusoTripAPI.shared.mutation(
                "freightClaims.processClaimPayment",
                input: ProcessClaimPaymentInput802(claimId: payment.claimId, amount: payment.amount,
                                                   method: releaseMethod(payment.method), reference: payment.reference,
                                                   notes: "Vessel claim payment release")
            )
            await load()
        } catch {
            loadError = error.eusoUserCopy
        }
    }

    private func exportStatement(_ value: ClaimPaymentsResp802) async {
        guard let claimId = value.payments.first?.claimId else { return }
        do {
            let report: ClaimReportResp802 = try await EusoTripAPI.shared.mutation(
                "freightClaims.generateClaimReport",
                input: ClaimReportInput802(claimId: claimId, format: "csv", includeEvidence: true,
                                           includeTimeline: true, includeFinancials: true, purpose: "internal")
            )
            if let content = report.content, !content.isEmpty { UIPasteboard.general.string = content }
        } catch {
            loadError = error.eusoUserCopy
        }
    }

    private func secondaryButton802(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44).background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        }.buttonStyle(.plain)
    }
}

private struct RimCard802<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

#Preview("802 · Claim Payments · Night") {
    VesselClaimPaymentsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("802 · Claim Payments · Light") {
    VesselClaimPaymentsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
