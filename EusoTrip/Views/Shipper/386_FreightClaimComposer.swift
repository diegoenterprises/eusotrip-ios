//
//  386_FreightClaimComposer.swift
//  EusoTrip - Shipper freight-claim composer.
//

import SwiftUI

struct FreightClaimComposerScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var initialClaimType: String = "damage"

    var body: some View {
        Shell(theme: theme) {
            ClaimComposerBody(loadId: loadId, initialClaimType: initialClaimType)
        } nav: {
            shipperLifecycleNav()
        }
    }
}

private struct ClaimComposerBody: View {
    @Environment(\.palette) private var palette

    let loadId: String

    @State private var claimType: FreightClaimsAPI.ClaimType?
    @State private var amountText = ""
    @State private var currencyText = ""
    @State private var expectedQuantityText = ""
    @State private var receivedQuantityText = ""
    @State private var quantityUnit = ""
    @State private var description = ""
    @State private var attachHistoricalWeather = false
    @State private var filing = false
    @State private var filingError: String?
    @State private var filedResult: FreightClaimsAPI.FileClaimResult?
    @State private var weatherOutcome: HistoricalWeatherOutcome?
    @State private var weatherError: String?
    @State private var fileRequestKey = UUID()
    @State private var weatherRequestKey = UUID()

    private let supportedTypes: [FreightClaimsAPI.ClaimType] = [
        .damage, .loss, .shortage, .delay, .contamination, .overcharge
    ]

    init(loadId: String, initialClaimType: String) {
        self.loadId = loadId
        let proposed = FreightClaimsAPI.ClaimType(rawValue: initialClaimType)
        let supported: Set<FreightClaimsAPI.ClaimType> = [
            .damage, .loss, .shortage, .delay, .contamination, .overcharge
        ]
        _claimType = State(initialValue: proposed.flatMap { supported.contains($0) ? $0 : nil })
    }

    private var canonicalLoadId: String {
        loadId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canonicalDescription: String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var amount: Double? {
        guard let value = Double(amountText.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite,
              value > 0 else { return nil }
        return value
    }

    private var currency: FreightClaimsAPI.CurrencyCode? {
        FreightClaimsAPI.CurrencyCode(rawValue: currencyText)
    }

    private var currencyIsValid: Bool {
        currencyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currency != nil
    }

    private var expectedQuantity: Double? { parsedQuantity(expectedQuantityText, allowsZero: false) }
    private var receivedQuantity: Double? { parsedQuantity(receivedQuantityText, allowsZero: true) }

    private var quantityIsValid: Bool {
        guard claimType == .shortage else { return true }
        guard let expectedQuantity, let receivedQuantity else { return false }
        return receivedQuantity < expectedQuantity
            && !quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantityUnit.trimmingCharacters(in: .whitespacesAndNewlines).count <= 32
    }

    private var canFile: Bool {
        !canonicalLoadId.isEmpty
            && claimType != nil
            && amount != nil
            && currencyIsValid
            && quantityIsValid
            && canonicalDescription.count >= 10
            && !filing
            && filedResult == nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let result = filedResult {
                    confirmationCard(result)
                } else {
                    transactionCard
                    typeCard
                    amountCard
                    if claimType == .shortage { quantityCard }
                    descriptionCard
                    weatherCard
                    validationCard
                    fileButton
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            EusoTripEyebrow(verbatim: "SHIPPER · FREIGHT CLAIM")
                .foregroundStyle(LinearGradient.primary)
            Text("File a freight claim")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Record the loss against one confirmed load transaction.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var transactionCard: some View {
        LifecycleCard {
            LifecycleSection(label: "TRANSACTION", icon: "shippingbox")
            keyValueRow("Mode", "Truck")
            keyValueRow("Load reference", canonicalLoadId.isEmpty ? "Unavailable" : canonicalLoadId)
        }
        .accessibilityElement(children: .combine)
    }

    private var typeCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CLAIM TYPE", icon: "tag")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(supportedTypes) { type in
                        Button {
                            claimType = type
                        } label: {
                            Label(type.label, systemImage: type.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(claimType == type ? Color.white : palette.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(
                                    claimType == type
                                        ? AnyShapeStyle(LinearGradient.diagonal)
                                        : AnyShapeStyle(palette.bgCardSoft)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(claimType == type ? .isSelected : [])
                    }
                }
            }
            if claimType == nil {
                Text("Choose a supported claim type before filing.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
            if claimType == .shortage {
                Text("Include the expected quantity, received quantity, and unit in the loss narrative, then add the supporting BOL or weight ticket to the filed claim.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var amountCard: some View {
        LifecycleCard {
            LifecycleSection(label: "CLAIM VALUE", icon: "banknote")
            TextField("Amount", text: $amountText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
                .accessibilityLabel("Claim amount")
            TextField("Currency code, optional", text: $currencyText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
                .accessibilityHint("Enter a three-letter currency code only when it is known")
            if !currencyIsValid {
                Text("Use a three-letter currency code, or leave it blank to use the load's recorded currency.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    private var descriptionCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LOSS NARRATIVE", icon: "text.alignleft")
            TextField("What happened, when, and where?", text: $description, axis: .vertical)
                .lineLimit(5...10)
                .textFieldStyle(.plain)
                .padding(12)
                .frame(minHeight: 132, alignment: .topLeading)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
            Text("Minimum 10 characters. Use only facts you can support.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var quantityCard: some View {
        LifecycleCard {
            LifecycleSection(label: "QUANTITY EVIDENCE", icon: "scalemass")
            TextField("Expected quantity", text: $expectedQuantityText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
            TextField("Received quantity", text: $receivedQuantityText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
            TextField("Unit, e.g. lb, kg, gal, bbl, MT", text: $quantityUnit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(palette.bgCardSoft)
                .overlay(fieldBorder)
            if !quantityIsValid {
                Text("A shortage requires a positive expected quantity, a lower non-negative received quantity, and its unit.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    private var weatherCard: some View {
        LifecycleCard {
            LifecycleSection(label: "HISTORICAL WEATHER EVIDENCE", icon: "cloud")
            Toggle(isOn: $attachHistoricalWeather) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Attach after the claim is filed")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Weather evidence is attached only when the claim narrative and cited provider records support a weather cause.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Brand.success)
            .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var validationCard: some View {
        if canonicalLoadId.isEmpty {
            messageCard("A confirmed load reference is required before this claim can be filed.", color: Brand.danger)
        }
        if let filingError {
            messageCard(filingError, color: Brand.danger)
        }
    }

    private var fileButton: some View {
        Button {
            Task { await fileClaim() }
        } label: {
            HStack(spacing: 8) {
                if filing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                }
                Text(filing ? "Filing claim..." : "File claim")
                    .font(EType.bodyStrong)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(canFile ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.neutral))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canFile)
        .accessibilityHint("Files this claim once, then verifies the recorded claim")
    }

    private func confirmationCard(_ result: FreightClaimsAPI.FileClaimResult) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "CONFIRMED CLAIM", icon: "checkmark.seal")
            Text(result.claimNumber)
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
            keyValueRow("Status", result.status.replacingOccurrences(of: "_", with: " ").capitalized)
            keyValueRow("Mode", result.transportMode.rawValue.capitalized)
            keyValueRow("Reference", result.referenceNumber)
            keyValueRow("Currency", result.currency.rawValue)
            weatherConfirmation
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claim \(result.claimNumber) confirmed from the live claim record")
    }

    @ViewBuilder
    private var weatherConfirmation: some View {
        if attachHistoricalWeather {
            if let weatherError {
                Text("Claim confirmed. Historical weather evidence was not attached: \(weatherError)")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let outcome = weatherOutcome {
                if outcome.attached {
                    Text("Historical weather evidence confirmed on the claim record.")
                        .font(EType.caption)
                        .foregroundStyle(Brand.success)
                } else {
                    Text(outcome.note ?? "Historical weather evidence is unavailable for this claim.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Checking historical weather evidence...")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1)
    }

    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 32)
    }

    private func messageCard(_ text: String, color: Color) -> some View {
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

    @MainActor
    private func fileClaim() async {
        guard canFile,
              let claimType,
              let amount else { return }

        filing = true
        filingError = nil
        weatherError = nil
        weatherOutcome = nil
        defer { filing = false }

        let request = FreightClaimsAPI.FileClaimRequest(
            reference: .truck(canonicalLoadId),
            type: claimType,
            amount: amount,
            currency: currency,
            description: canonicalDescription,
            commodity: nil,
            weight: nil,
            weightUnit: nil,
            expectedQuantity: claimType == .shortage ? expectedQuantity : nil,
            receivedQuantity: claimType == .shortage ? receivedQuantity : nil,
            quantityUnit: claimType == .shortage ? optionalText(quantityUnit) : nil,
            damageExtent: nil,
            discoveredAt: nil,
            evidenceIds: nil,
            requestKey: fileRequestKey
        )

        do {
            let result = try await EusoTripAPI.shared.shipperFreightClaims.fileClaim(request)
            try validateAcknowledgement(result, request: request)
            guard let detail = try await EusoTripAPI.shared.shipperFreightClaims.getClaimById(id: result.claimId) else {
                throw ClaimComposerConfirmationError.missingReadback
            }
            try validateReadback(detail, result: result)
            filedResult = result

            if attachHistoricalWeather {
                await attachWeatherEvidence(to: result.claimId)
            }
        } catch {
            filingError = (error as? LocalizedError)?.errorDescription ?? error.eusoUserCopy
        }
    }

    private func parsedQuantity(_ text: String, allowsZero: Bool) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite,
              allowsZero ? value >= 0 : value > 0 else { return nil }
        return value
    }

    private func optionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func validateAcknowledgement(
        _ result: FreightClaimsAPI.FileClaimResult,
        request: FreightClaimsAPI.FileClaimRequest
    ) throws {
        guard result.status == FreightClaimsAPI.ClaimStatus.filed.rawValue else {
            throw ClaimComposerConfirmationError.unexpectedStatus(result.status)
        }
        guard result.transportMode == .truck,
              result.transportMode == request.reference.transportMode,
              result.referenceNumber == canonicalLoadId else {
            throw ClaimComposerConfirmationError.transactionMismatch
        }
        if let requestedCurrency = request.currency,
           result.currency != requestedCurrency {
            throw ClaimComposerConfirmationError.currencyMismatch
        }
        if request.type == .shortage,
           (result.expectedQuantity != request.expectedQuantity ||
            result.receivedQuantity != request.receivedQuantity ||
            result.quantityUnit != request.quantityUnit) {
            throw ClaimComposerConfirmationError.quantityMismatch
        }
    }

    private func validateReadback(
        _ detail: FreightClaimsAPI.ClaimDetail,
        result: FreightClaimsAPI.FileClaimResult
    ) throws {
        guard detail.claimId == result.claimId,
              detail.status == result.status,
              (detail.transportMode ?? detail.load.transportMode) == .truck,
              detail.load.referenceNumber == result.referenceNumber,
              detail.currency == result.currency else {
            throw ClaimComposerConfirmationError.readbackMismatch
        }
        if result.expectedQuantity != nil || result.receivedQuantity != nil || result.quantityUnit != nil {
            guard detail.quantityEvidence.state == "recorded",
                  detail.quantityEvidence.source != nil,
                  detail.quantityEvidence.expectedQuantity == result.expectedQuantity,
                  detail.quantityEvidence.receivedQuantity == result.receivedQuantity,
                  detail.quantityEvidence.quantityUnit == result.quantityUnit else {
                throw ClaimComposerConfirmationError.quantityMismatch
            }
        }
    }

    @MainActor
    private func attachWeatherEvidence(to claimId: String) async {
        struct Input: Encodable {
            let claimId: String
            let requestKey: String
        }

        do {
            let outcome: HistoricalWeatherOutcome = try await EusoTripAPI.shared.mutation(
                "freightClaims.attachHistoricalWeatherEvidence",
                input: Input(
                    claimId: claimId,
                    requestKey: weatherRequestKey.uuidString.lowercased()
                )
            )
            guard outcome.claimId == claimId else {
                throw ClaimComposerConfirmationError.weatherClaimMismatch
            }
            if outcome.attached {
                guard outcome.available,
                      let evidenceId = outcome.evidence?.id,
                      let detail = try await EusoTripAPI.shared.shipperFreightClaims.getClaimById(id: claimId),
                      detail.evidence.contains(where: { $0.id == evidenceId }) else {
                    throw ClaimComposerConfirmationError.weatherReadbackMismatch
                }
            }
            weatherOutcome = outcome
        } catch {
            weatherError = (error as? LocalizedError)?.errorDescription ?? error.eusoUserCopy
        }
    }
}

private struct HistoricalWeatherOutcome: Decodable {
    struct Evidence: Decodable {
        let id: String?
    }

    let claimId: String
    let available: Bool
    let attached: Bool
    let reason: String?
    let note: String?
    let evidence: Evidence?
}

private enum ClaimComposerConfirmationError: LocalizedError {
    case missingReadback
    case readbackMismatch
    case transactionMismatch
    case currencyMismatch
    case quantityMismatch
    case unexpectedStatus(String)
    case weatherClaimMismatch
    case weatherReadbackMismatch

    var errorDescription: String? {
        switch self {
        case .missingReadback:
            return "The claim was accepted, but its record is not available yet. Retry with the same request."
        case .readbackMismatch:
            return "The filed claim did not match the confirmed transaction. Nothing has been presented as complete."
        case .transactionMismatch:
            return "The confirmation did not match this truck load. Nothing has been reported as complete."
        case .currencyMismatch:
            return "The confirmed claim uses a different currency. Nothing has been reported as complete."
        case .quantityMismatch:
            return "The confirmed claim uses different quantity evidence. Nothing has been reported as complete."
        case .unexpectedStatus(let status):
            return "The claim returned an unexpected status (\(status)). Nothing has been reported as complete."
        case .weatherClaimMismatch:
            return "The weather-evidence acknowledgement referenced a different claim."
        case .weatherReadbackMismatch:
            return "Weather evidence was acknowledged but could not be confirmed on the claim record."
        }
    }
}
