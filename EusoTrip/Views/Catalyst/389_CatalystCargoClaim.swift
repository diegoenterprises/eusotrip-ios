//
//  389_CatalystCargoClaim.swift
//  EusoTrip - Catalyst cargo-claim adjudication.
//

import SwiftUI

struct CatalystCargoClaimScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            CatalystCargoClaim_389()
        } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .loads),
                trailing: CarrierNavRoute.trailing(current: .loads),
                orbState: .idle
            )
        }
    }
}

private struct CatalystCargoClaim_389: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var claim: FreightClaimsAPI.Claim?
    @State private var detail: FreightClaimsAPI.ClaimDetail?
    @State private var activeClaimCount: Int?
    @State private var loading = true
    @State private var loadError: String?
    @State private var detailError: String?
    @State private var presentingDecision = false
    @State private var confirmation: ClaimDecisionResult?

    private static let activeStatuses: Set<String> = [
        "filed", "under_review", "investigating", "pending_evidence",
        "approved", "partial_approval", "counter_offer"
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                IridescentHairline()
                    .padding(.horizontal, -20)

                if loading {
                    loadingCard
                } else if let loadError {
                    errorCard(loadError)
                } else if let claim {
                    heroCard(claim)
                    detailLedger(claim)
                    responseRegister
                    transactionCard(claim)
                    if let confirmation {
                        confirmationCard(confirmation)
                    }
                    decisionButton
                } else {
                    emptyCard
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await reload() }
        .eusoRefreshHandler { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $presentingDecision) {
            if let claim {
                ClaimDecisionSheet389(claim: claim, detail: detail) { result in
                    confirmation = result
                    Task { await reload(preserveConfirmation: true) }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12)
                Text("CATALYST · CARGO CLAIM")
                    .font(EType.micro)
                    .tracking(1)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 12)
            Text(claimReference)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(palette.bgCardSoft)
                    .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 3) {
                Text("Cargo claim")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Carrier review · truck claims")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var loadingCard: some View {
        LifecycleCard {
            ProgressView()
            Text("Loading the live claim register...")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityLabel("Loading the live claim register")
    }

    private var emptyCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LIVE REGISTER", icon: "shippingbox")
            Text("No truck cargo claims")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text("No truck-mode freight claim is visible to this carrier company.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func errorCard(_ message: String) -> some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "CLAIMS UNAVAILABLE", icon: "exclamationmark.triangle")
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
            Button {
                Task { await reload() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .frame(minWidth: 88, minHeight: 44)
            }
            .buttonStyle(.bordered)
        }
    }

    private func heroCard(_ claim: FreightClaimsAPI.Claim) -> some View {
        let status = detail?.status ?? claim.status
        return LifecycleCard(accentGradient: true) {
            HStack(alignment: .firstTextBaseline) {
                Text(claim.claimNumber)
                    .font(EType.mono(.body))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                statusLabel(status)
            }
            Text(money(detail?.amount ?? claim.amount, currency: detail?.currency ?? claim.currency))
                .font(.system(size: 30, weight: .heavy).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
            Text("Claimed value")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Text(detail?.description ?? claim.description ?? "Claim narrative unavailable")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func detailLedger(_ claim: FreightClaimsAPI.Claim) -> some View {
        LifecycleCard {
            LifecycleSection(label: "CLAIM DETAIL", icon: "list.bullet.rectangle")
            ledgerRow("Claim type", pretty(detail?.type ?? claim.type))
            ledgerRow("Claimed amount", money(detail?.amount ?? claim.amount, currency: detail?.currency ?? claim.currency))
            ledgerRow("Filed", detail?.filedDate ?? claim.filedDate)
            ledgerRow("Carrier", carrierName(claim))
            ledgerRow("Evidence", evidenceSummary)
            ledgerRow("Workflow", workflowSummary)
            if let detailError {
                Text(detailError)
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var responseRegister: some View {
        LifecycleCard {
            LifecycleSection(label: "CARRIER RESPONSE", icon: "checklist")
            ledgerRow("Open or pending", activeClaimCount.map(String.init) ?? "—")
            Text("Count is scoped to truck claims visible to the signed-in company.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func transactionCard(_ claim: FreightClaimsAPI.Claim) -> some View {
        LifecycleCard {
            LifecycleSection(label: "TRANSACTION", icon: "link")
            ledgerRow("Mode", transportMode(claim))
            ledgerRow("Reference", transactionReference(claim))
            ledgerRow("Shipper", shipperName(claim))
            if let context = detail?.load {
                ledgerRow("Origin", context.origin ?? "Unavailable")
                ledgerRow("Destination", context.destination ?? "Unavailable")
                ledgerRow("Commodity", context.commodity ?? "Unavailable")
            }
        }
    }

    private var decisionButton: some View {
        Button {
            presentingDecision = true
        } label: {
            Label("Review claim decision", systemImage: "checkmark.seal")
                .font(EType.bodyStrong)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the claim decision form")
    }

    private func confirmationCard(_ result: ClaimDecisionResult) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "CONFIRMED DECISION", icon: "checkmark.seal")
            ledgerRow("Decision", result.decision.label)
            ledgerRow("Mode", result.transportMode.rawValue.capitalized)
            ledgerRow("Reference", result.referenceNumber)
            ledgerRow("Currency", result.currency.rawValue)
            if let amount = result.amount {
                ledgerRow("Amount", money(amount, currency: result.currency))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claim decision confirmed in the live claim record")
    }

    private func ledgerRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 34)
    }

    private func statusLabel(_ status: String?) -> some View {
        let label = pretty(status)
        let color = statusColor(status)
        return Text(label.uppercased())
            .font(EType.micro)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(color.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var claimReference: String {
        claim?.claimNumber ?? "—"
    }

    private func transactionReference(_ claim: FreightClaimsAPI.Claim) -> String {
        detail?.load.referenceNumber
            ?? claim.referenceNumber
            ?? claim.loadNumber
            ?? "Unavailable"
    }

    private func transportMode(_ claim: FreightClaimsAPI.Claim) -> String {
        (detail?.transportMode ?? detail?.load.transportMode ?? claim.transportMode)?.rawValue.capitalized
            ?? "Unavailable"
    }

    private func carrierName(_ claim: FreightClaimsAPI.Claim) -> String {
        detail?.carrier?.name
            ?? claim.carrier
            ?? "Unavailable"
    }

    private func shipperName(_ claim: FreightClaimsAPI.Claim) -> String {
        detail?.shipper?.name
            ?? claim.shipper
            ?? "Unavailable"
    }

    private var evidenceSummary: String {
        guard let detail else { return "Unavailable" }
        return detail.evidence.isEmpty ? "No evidence attached" : "\(detail.evidence.count) attached"
    }

    private var workflowSummary: String {
        guard let workflow = detail?.workflow else { return "Unavailable" }
        return "Step \(workflow.currentStep) of \(workflow.steps.count)"
    }

    private func pretty(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Unknown" }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func statusColor(_ raw: String?) -> Color {
        switch (raw ?? "").lowercased() {
        case "filed", "under_review", "investigating", "pending_evidence":
            return Brand.warning
        case "approved", "partial_approval", "counter_offer":
            return Brand.info
        case "settled", "paid", "closed":
            return Brand.success
        case "denied":
            return Brand.danger
        default:
            return palette.textSecondary
        }
    }

    private func money(
        _ amount: Double?,
        currency: FreightClaimsAPI.CurrencyCode?
    ) -> String {
        guard let amount, let currency else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount))
            ?? "\(currency.rawValue) \(amount.formatted(.number.precision(.fractionLength(2))))"
    }

    @MainActor
    private func reload(preserveConfirmation: Bool = false) async {
        loading = true
        loadError = nil
        detailError = nil
        if !preserveConfirmation {
            confirmation = nil
        }

        do {
            let response = try await EusoTripAPI.shared.freightClaims.getClaims(
                transportMode: .truck,
                limit: 50
            )
            activeClaimCount = response.claims.filter {
                Self.activeStatuses.contains(($0.status ?? "").lowercased())
            }.count
            guard let first = response.claims.first else {
                claim = nil
                detail = nil
                loading = false
                return
            }
            claim = first
            do {
                detail = try await EusoTripAPI.shared.freightClaims.getClaimById(id: first.claimId)
                if detail == nil {
                    detailError = "Claim detail is unavailable for this register row."
                }
            } catch {
                detail = nil
                detailError = error.eusoUserCopy
            }
        } catch {
            claim = nil
            detail = nil
            activeClaimCount = nil
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

private enum ClaimDecision389: String, CaseIterable, Identifiable, Codable, Hashable {
    case approve
    case partial
    case deny
    case counterOffer = "counter_offer"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .approve: return "Approve"
        case .partial: return "Partial approval"
        case .deny: return "Deny"
        case .counterOffer: return "Counter offer"
        }
    }

    var requiresAmount: Bool {
        self != .deny
    }

    var expectedReadbackStatus: String {
        switch self {
        case .approve, .partial: return "paid"
        case .deny: return "denied"
        case .counterOffer: return "counter_offer"
        }
    }
}

private struct ClaimDecisionInput: Encodable {
    let claimId: String
    let decision: ClaimDecision389
    let approvedAmount: Double?
    let counterOfferAmount: Double?
    let reason: String
    let conditions: String?
    let idempotencyKey: String
}

private struct ClaimDecisionResult: Decodable, Hashable {
    let success: Bool
    let claimId: String
    let decision: ClaimDecision389
    let amount: Double?
    let currency: FreightClaimsAPI.CurrencyCode
    let transportMode: FreightClaimsAPI.TransportMode
    let referenceNumber: String
    let paymentId: String?
    let idempotent: Bool
    let decidedAt: String
}

private struct ClaimDecisionSheet389: View {
    let claim: FreightClaimsAPI.Claim
    let detail: FreightClaimsAPI.ClaimDetail?
    let onConfirmed: (ClaimDecisionResult) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var decision: ClaimDecision389 = .approve
    @State private var amountText = ""
    @State private var reason = ""
    @State private var conditions = ""
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var confirmed: ClaimDecisionResult?
    @State private var requestKey = UUID()

    private var claimAmount: Double? {
        detail?.amount ?? claim.amount
    }

    private var claimCurrency: FreightClaimsAPI.CurrencyCode? {
        detail?.currency ?? claim.currency
    }

    private var transactionReference: String? {
        detail?.load.referenceNumber ?? claim.referenceNumber ?? claim.loadNumber
    }

    private var amount: Double? {
        guard let value = Double(amountText.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite,
              value > 0 else { return nil }
        return value
    }

    private var canSubmit: Bool {
        guard confirmed == nil,
              !submitting,
              reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else {
            return false
        }
        if decision.requiresAmount {
            guard amount != nil, claimCurrency != nil else { return false }
        }
        if decision == .approve || decision == .partial,
           let amount,
           let claimAmount,
           amount > claimAmount {
            return false
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    claimContext
                    decisionControl
                    if decision.requiresAmount {
                        amountControl
                    }
                    reasonControl
                    if decision == .approve || decision == .partial {
                        conditionsControl
                    }
                    if let errorMessage {
                        message(errorMessage, color: Brand.danger)
                    }
                    if let confirmed {
                        confirmation(confirmed)
                    } else {
                        submitButton
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(16)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Claim decision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(confirmed == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private var claimContext: some View {
        LifecycleCard {
            LifecycleSection(label: "CLAIM", icon: "shippingbox")
            row("Claim", claim.claimNumber)
            row("Mode", "Truck")
            row("Reference", transactionReference ?? "Unavailable")
            row("Claimed", money(claimAmount, currency: claimCurrency))
        }
    }

    private var decisionControl: some View {
        LifecycleCard {
            LifecycleSection(label: "DECISION", icon: "checkmark.seal")
            Picker("Decision", selection: $decision) {
                ForEach(ClaimDecision389.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            .onChange(of: decision) { _, _ in
                errorMessage = nil
            }
        }
    }

    private var amountControl: some View {
        LifecycleCard {
            LifecycleSection(label: "DECISION AMOUNT", icon: "banknote")
            TextField("Amount", text: $amountText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
            Text(claimCurrency.map { "Currency: \($0.rawValue)" } ?? "The transaction currency is unavailable. Money-moving decisions are blocked.")
                .font(EType.caption)
                .foregroundStyle(claimCurrency == nil ? Brand.warning : palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if (decision == .approve || decision == .partial),
               let amount,
               let claimAmount,
               amount > claimAmount {
                Text("The approved amount cannot exceed the filed claim amount.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    private var reasonControl: some View {
        LifecycleCard {
            LifecycleSection(label: "REASON", icon: "text.alignleft")
            TextField("Decision rationale", text: $reason, axis: .vertical)
                .lineLimit(4...8)
                .textFieldStyle(.plain)
                .padding(12)
                .frame(minHeight: 112, alignment: .topLeading)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
        }
    }

    private var conditionsControl: some View {
        LifecycleCard {
            LifecycleSection(label: "CONDITIONS", icon: "list.bullet")
            TextField("Optional settlement conditions", text: $conditions, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(12)
                .frame(minHeight: 72, alignment: .topLeading)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                }
                Text(submitting ? "Confirming..." : "Submit decision")
                    .font(EType.bodyStrong)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(canSubmit ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.neutral))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityHint("Submits this decision once and confirms the resulting claim status")
    }

    private func confirmation(_ result: ClaimDecisionResult) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "CONFIRMED", icon: "checkmark.seal")
            row("Decision", result.decision.label)
            row("Status", result.decision.expectedReadbackStatus.replacingOccurrences(of: "_", with: " ").capitalized)
            row("Reference", result.referenceNumber)
            row("Currency", result.currency.rawValue)
            if let amount = result.amount {
                row("Amount", money(amount, currency: result.currency))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 34)
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(EType.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func money(
        _ amount: Double?,
        currency: FreightClaimsAPI.CurrencyCode?
    ) -> String {
        guard let amount, let currency else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount))
            ?? "\(currency.rawValue) \(amount.formatted(.number.precision(.fractionLength(2))))"
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        errorMessage = nil
        defer { submitting = false }

        let approvedAmount = decision == .approve || decision == .partial ? amount : nil
        let counterAmount = decision == .counterOffer ? amount : nil
        let input = ClaimDecisionInput(
            claimId: claim.claimId,
            decision: decision,
            approvedAmount: approvedAmount,
            counterOfferAmount: counterAmount,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            conditions: optionalText(conditions),
            idempotencyKey: requestKey.uuidString.lowercased()
        )

        do {
            let result: ClaimDecisionResult = try await EusoTripAPI.shared.mutation(
                "freightClaims.submitClaimDecision",
                input: input
            )
            try validateAcknowledgement(result)
            guard let readback = try await EusoTripAPI.shared.freightClaims.getClaimById(id: claim.claimId) else {
                throw ClaimDecisionConfirmationError.missingReadback
            }
            try validateReadback(readback, result: result)
            confirmed = result
            onConfirmed(result)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.eusoUserCopy
        }
    }

    private func validateAcknowledgement(_ result: ClaimDecisionResult) throws {
        guard result.success,
              result.claimId == claim.claimId,
              result.decision == decision else {
            throw ClaimDecisionConfirmationError.acknowledgementMismatch
        }
        guard result.transportMode == .truck else {
            throw ClaimDecisionConfirmationError.transactionMismatch
        }
        if let transactionReference,
           result.referenceNumber != transactionReference {
            throw ClaimDecisionConfirmationError.transactionMismatch
        }
        if let claimCurrency,
           result.currency != claimCurrency {
            throw ClaimDecisionConfirmationError.currencyMismatch
        }
        let expectedAmount = decision == .counterOffer ? amount : (decision == .deny ? nil : amount)
        if let expectedAmount {
            guard let returnedAmount = result.amount,
                  abs(returnedAmount - expectedAmount) < 0.005 else {
                throw ClaimDecisionConfirmationError.amountMismatch
            }
        } else if result.amount != nil {
            throw ClaimDecisionConfirmationError.amountMismatch
        }
    }

    private func validateReadback(
        _ readback: FreightClaimsAPI.ClaimDetail,
        result: ClaimDecisionResult
    ) throws {
        guard readback.claimId == result.claimId,
              readback.status == decision.expectedReadbackStatus,
              (readback.transportMode ?? readback.load.transportMode) == .truck,
              readback.load.referenceNumber == result.referenceNumber,
              readback.currency == result.currency else {
            throw ClaimDecisionConfirmationError.readbackMismatch
        }
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum ClaimDecisionConfirmationError: LocalizedError {
    case acknowledgementMismatch
    case transactionMismatch
    case currencyMismatch
    case amountMismatch
    case missingReadback
    case readbackMismatch

    var errorDescription: String? {
        switch self {
        case .acknowledgementMismatch:
            return "The decision acknowledgement did not match the submitted decision."
        case .transactionMismatch:
            return "The decision acknowledgement referenced a different truck transaction."
        case .currencyMismatch:
            return "The decision acknowledgement returned a different currency."
        case .amountMismatch:
            return "The decision acknowledgement returned a different amount."
        case .missingReadback:
            return "The decision was acknowledged but the claim could not be read back."
        case .readbackMismatch:
            return "The live claim record does not yet reflect the acknowledged decision."
        }
    }
}

#Preview("389 · Catalyst · Cargo Claim · Night") {
    CatalystCargoClaimScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}
