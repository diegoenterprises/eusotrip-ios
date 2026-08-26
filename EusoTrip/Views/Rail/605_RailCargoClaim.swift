//
//  605_RailCargoClaim.swift
//  EusoTrip
//
//  Purpose: let a rail operator inspect one server-confirmed cargo claim without
//  changing its shipment, money, quantity, party, or evidence context.
//  Archetype: claim proof register.
//

import Foundation
import SwiftUI

enum FreightClaimConsumerContractError: LocalizedError {
    case missingClaim
    case wrongMode(expected: FreightClaimsAPI.TransportMode)
    case missingTransactionReference(mode: FreightClaimsAPI.TransportMode)
    case inconsistentPage

    var errorDescription: String? {
        switch self {
        case .missingClaim:
            return "That claim is no longer available to this account."
        case .wrongMode(let expected):
            return "This claim is not linked to a \(expected.rawValue.lowercased()) transaction."
        case .missingTransactionReference(let mode):
            let noun: String
            switch mode {
            case .rail: noun = "rail shipment"
            case .vessel: noun = "vessel booking"
            case .truck: noun = "truck load"
            }
            return "This claim is missing its \(noun) reference."
        case .inconsistentPage:
            return "The claims register changed while it was loading. Pull down to refresh it."
        }
    }
}

/// Shared presentation-only rules for the bounded rail/vessel claim consumers.
/// No value is synthesized: incomplete financial or quantity context stays
/// explicitly incomplete, and every detail read is mode- and anchor-checked.
enum FreightClaimConsumerCanon {
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-", trimmed != "—" else { return nil }
        return trimmed
    }

    static func label(_ value: String?) -> String? {
        guard let value = clean(value) else { return nil }
        return value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    static func financialContext(
        amount: Double?,
        currency: FreightClaimsAPI.CurrencyCode?
    ) -> String? {
        switch (amount, currency) {
        case let (.some(amount), .some(currency)):
            return "\(currency.rawValue) \(amount.formatted(.number.precision(.fractionLength(2))))"
        case let (.some(amount), .none):
            return "\(amount.formatted(.number.precision(.fractionLength(2)))) · currency unavailable"
        case let (.none, .some(currency)):
            return "Amount unavailable · \(currency.rawValue)"
        case (.none, .none):
            return nil
        }
    }

    static func quantityContext(amount: Double?, unit: String?) -> String? {
        guard let amount else { return nil }
        let rendered = amount.formatted(.number.precision(.fractionLength(0...3)))
        guard let unit = clean(unit) else { return "\(rendered) · unit unavailable" }
        return "\(rendered) \(unit)"
    }

    static func reference(
        for claim: FreightClaimsAPI.Claim,
        mode: FreightClaimsAPI.TransportMode
    ) -> String? {
        switch mode {
        case .rail:
            return clean(claim.railShipmentNumber) ?? clean(claim.referenceNumber)
        case .vessel:
            return clean(claim.vesselBookingNumber) ?? clean(claim.referenceNumber)
        case .truck:
            return clean(claim.loadNumber) ?? clean(claim.referenceNumber)
        }
    }

    static func reference(
        for detail: FreightClaimsAPI.ClaimDetail,
        mode: FreightClaimsAPI.TransportMode
    ) -> String? {
        guard detail.transportMode == mode else { return nil }
        return clean(detail.load.referenceNumber)
    }

    static func claims(
        mode: FreightClaimsAPI.TransportMode
    ) async throws -> [FreightClaimsAPI.Claim] {
        var records: [FreightClaimsAPI.Claim] = []
        var offset = 0
        var expectedTotal: Int?

        while expectedTotal == nil || records.count < expectedTotal! {
            let page = try await EusoTripAPI.shared.freightClaims.getClaims(
                transportMode: mode,
                limit: 100,
                offset: offset
            )
            if let expectedTotal, expectedTotal != page.total {
                throw FreightClaimConsumerContractError.inconsistentPage
            }
            expectedTotal = page.total
            guard !page.claims.isEmpty else {
                if records.count == page.total { break }
                throw FreightClaimConsumerContractError.inconsistentPage
            }
            guard page.claims.allSatisfy({ $0.transportMode == mode }) else {
                throw FreightClaimConsumerContractError.wrongMode(expected: mode)
            }
            records.append(contentsOf: page.claims)
            offset = records.count
        }

        guard Set(records.map(\.claimId)).count == records.count else {
            throw FreightClaimConsumerContractError.inconsistentPage
        }
        return records
    }

    static func detail(
        claimId: String,
        mode: FreightClaimsAPI.TransportMode
    ) async throws -> FreightClaimsAPI.ClaimDetail? {
        let requestedId = clean(claimId)
        let resolvedId: String
        if let requestedId {
            resolvedId = requestedId
        } else {
            let page = try await EusoTripAPI.shared.freightClaims.getClaims(
                transportMode: mode,
                limit: 1,
                offset: 0
            )
            guard let first = page.claims.first else { return nil }
            guard first.transportMode == mode else {
                throw FreightClaimConsumerContractError.wrongMode(expected: mode)
            }
            resolvedId = first.claimId
        }

        guard let detail = try await EusoTripAPI.shared.freightClaims.getClaimById(id: resolvedId) else {
            throw FreightClaimConsumerContractError.missingClaim
        }
        guard detail.transportMode == mode else {
            throw FreightClaimConsumerContractError.wrongMode(expected: mode)
        }
        guard reference(for: detail, mode: mode) != nil else {
            throw FreightClaimConsumerContractError.missingTransactionReference(mode: mode)
        }
        return detail
    }

    static func errorMessage(_ error: Error) -> String {
        if let contract = error as? FreightClaimConsumerContractError {
            return contract.errorDescription ?? "Claims could not be refreshed."
        }
        if let api = error as? EusoTripAPIError {
            switch api {
            case .unauthenticated:
                return "Your session expired. Sign in again to view claims."
            case .forbidden(let message):
                return clean(message) ?? "This account does not have access to these claims."
            case .httpStatus(let code, _):
                if code == 401 { return "Your session expired. Sign in again to view claims." }
                if code == 403 { return "This account does not have access to these claims." }
                return "Claims could not be refreshed. EusoTrip returned error \(code)."
            case .notConfigured, .badURL:
                return "Claims are unavailable because this app installation is not configured."
            case .decodingFailed:
                return "Claims were returned in a format this app cannot safely read."
            case .trpcError(let message):
                return clean(message) ?? "Claims could not be refreshed."
            case .empty:
                return "The claim could not be loaded. Refresh to try again."
            case .queuedForOfflineReplay:
                return "Claims cannot be read while this device is offline."
            }
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return "Claims cannot be refreshed while this device is offline."
        }
        return "Claims could not be refreshed."
    }
}

struct FreightClaimSurfaceHeader: View {
    @Environment(\.palette) private var palette
    let context: String
    let title: String
    let purpose: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                EusoTripBrandMark(size: 14)
                Text(context)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LinearGradient.primary)
            }
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(purpose)
                .font(.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            IridescentHairline()
        }
    }
}

struct FreightClaimValueRow: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String?
    var unavailable: String = "Unavailable"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Space.s3)
            Text(value ?? unavailable)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(value == nil ? palette.textTertiary : palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

struct FreightClaimEvidenceRegister: View {
    @Environment(\.palette) private var palette
    let evidence: [FreightClaimsAPI.EvidenceRecord]

    var body: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                Label("Evidence register", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.bottom, Space.s2)
                if evidence.isEmpty {
                    Text("No evidence is attached to this claim.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                        .frame(minHeight: 44)
                } else {
                    ForEach(Array(evidence.enumerated()), id: \.element.id) { index, record in
                        if index > 0 { Divider().opacity(0.25) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FreightClaimConsumerCanon.clean(record.name) ?? "Unnamed evidence")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                            HStack(spacing: Space.s2) {
                                if let type = FreightClaimConsumerCanon.label(record.type) {
                                    Text(type)
                                }
                                if let uploadedAt = FreightClaimConsumerCanon.clean(record.uploadedAt) {
                                    Text(uploadedAt)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

struct FreightClaimWorkflowRegister: View {
    @Environment(\.palette) private var palette
    let workflow: FreightClaimsAPI.Workflow

    var body: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                Label("Claim workflow", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.bottom, Space.s2)
                ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { Divider().opacity(0.25) }
                    HStack(spacing: Space.s3) {
                        Image(systemName: step.completed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.completed ? Brand.success : palette.textTertiary)
                            .accessibilityHidden(true)
                        Text(step.name)
                            .font(.subheadline)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        if step.step == workflow.currentStep {
                            Text("Current")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.info)
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private enum FreightClaimLifecycleRecorderSheet: String, Identifiable {
    case asset
    case deadline
    case reserve

    var id: String { rawValue }
}

/// Shared rail/vessel write surface for typed claim assets and authority-backed
/// deadlines. A command is considered complete only after a matching record is
/// returned by `getClaimById`; mutation acknowledgements alone never become UI
/// truth.
struct FreightClaimLifecycleRecorder: View {
    @Environment(\.palette) private var palette
    @Binding var claim: FreightClaimsAPI.ClaimDetail?
    @Binding var error: String?
    let mode: FreightClaimsAPI.TransportMode

    @State private var activeSheet: FreightClaimLifecycleRecorderSheet?

    var body: some View {
        Group {
            if let claim,
               claim.lifecycleCapabilities.recordAsset.allowed ||
                claim.lifecycleCapabilities.recordDeadline.allowed ||
                claim.lifecycleCapabilities.setReserve.allowed {
                LifecycleCard {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Add lifecycle evidence")
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Record a typed transaction asset or an authority-backed clock. Nothing is inferred from unstructured claim text.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if claim.lifecycleCapabilities.recordAsset.allowed {
                            Button {
                                activeSheet = .asset
                            } label: {
                                Label("Record typed asset", systemImage: "doc.badge.plus")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityHint("Opens a form for a mode-valid claim asset and its provenance.")
                        }

                        if claim.lifecycleCapabilities.recordDeadline.allowed {
                            Button {
                                activeSheet = .deadline
                            } label: {
                                Label("Record deadline", systemImage: "calendar.badge.plus")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Opens a form for a claim deadline and its governing authority.")
                        }

                        if claim.lifecycleCapabilities.setReserve.allowed {
                            Button {
                                activeSheet = .reserve
                            } label: {
                                Label("Set reserve", systemImage: "banknote")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Opens a form for a versioned reserve in the locked claim currency.")
                        }
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            if let currentClaim = claim {
                switch sheet {
                case .asset:
                    FreightClaimAssetRecordForm(
                        claim: currentClaim,
                        mode: mode,
                        requiresCompanySelection: currentClaim.lifecycleCapabilities.recordAsset.requiresCompanySelection
                    ) { refreshed in
                        claim = refreshed
                        error = nil
                    }
                case .deadline:
                    FreightClaimDeadlineRecordForm(
                        claim: currentClaim,
                        mode: mode,
                        requiresCompanySelection: currentClaim.lifecycleCapabilities.recordDeadline.requiresCompanySelection
                    ) { refreshed in
                        claim = refreshed
                        error = nil
                    }
                case .reserve:
                    FreightClaimReserveRecordForm(
                        claim: currentClaim,
                        mode: mode
                    ) { refreshed in
                        claim = refreshed
                        error = nil
                    }
                }
            } else {
                ContentUnavailableView(
                    "Claim unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Dismiss this form and refresh the claim before recording a lifecycle item.")
                )
            }
        }
    }
}

private enum FreightClaimLifecycleWriteCanon {
    struct CompanyOption: Identifiable, Hashable {
        let id: Int
        let label: String
    }

    static func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func companies(for claim: FreightClaimsAPI.ClaimDetail) -> [CompanyOption] {
        var options: [CompanyOption] = []
        for party in [claim.claimant, claim.respondent].compactMap({ $0 }) {
            guard let id = Int(party.id), id > 0 else { continue }
            let name = FreightClaimConsumerCanon.clean(party.name) ?? "Company \(id)"
            if !options.contains(where: { $0.id == id }) {
                options.append(CompanyOption(id: id, label: name))
            }
        }
        return options
    }

    static func assetTypes(for mode: FreightClaimsAPI.TransportMode) -> [FreightClaimsAPI.ClaimAssetType] {
        switch mode {
        case .truck:
            return [.billOfLading, .trailer, .seal, .deliveryReceipt, .surveyReport, .other]
        case .rail:
            return [.billOfLading, .railcar, .seal, .deliveryReceipt, .surveyReport, .other]
        case .vessel:
            return [.billOfLading, .container, .parcel, .seal, .deliveryReceipt, .surveyReport, .other]
        }
    }

    static func quantity(_ raw: String, unit rawUnit: String) -> (value: Double?, unit: String?)? {
        let amount = clean(raw)
        let unit = clean(rawUnit)
        guard (amount == nil) == (unit == nil) else { return nil }
        guard let amount else { return (nil, nil) }
        guard let value = Double(amount), value.isFinite, value >= 0 else { return nil }
        return (value, unit)
    }

    static func reserveAmount(_ raw: String) -> Double? {
        guard let cleaned = clean(raw),
              let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0,
              decimal <= Decimal(string: "99999999999.99")! else { return nil }
        var source = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 2, .plain)
        guard rounded == decimal else { return nil }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    static func datesMatch(_ value: String?, _ expected: Date?) -> Bool {
        switch (parseDate(value), expected) {
        case let (.some(actual), .some(expected)):
            return abs(actual.timeIntervalSince(expected)) < 1
        case (.none, .none):
            return true
        default:
            return false
        }
    }

    static func quantitiesMatch(_ actual: Double?, _ expected: Double?) -> Bool {
        switch (actual, expected) {
        case let (.some(actual), .some(expected)):
            return abs(actual - expected) < 0.000_001
        case (.none, .none):
            return true
        default:
            return false
        }
    }

    static func validSourceURI(_ value: String?) -> Bool {
        guard let value else { return true }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return false }
        return true
    }
}

private struct FreightClaimAssetRecordForm: View {
    @Environment(\.dismiss) private var dismiss
    let claim: FreightClaimsAPI.ClaimDetail
    let mode: FreightClaimsAPI.TransportMode
    let requiresCompanySelection: Bool
    let onConfirmed: (FreightClaimsAPI.ClaimDetail) -> Void

    @State private var selectedCompanyId: Int?
    @State private var assetType: FreightClaimsAPI.ClaimAssetType?
    @State private var identifier = ""
    @State private var quantity = ""
    @State private var quantityUnit = ""
    @State private var provenance: FreightClaimsAPI.ClaimAssetProvenance?
    @State private var sourceProvider = ""
    @State private var sourceReference = ""
    @State private var hasObservedAt = false
    @State private var observedAt = Date()
    @State private var requestKey: UUID?
    @State private var requestFingerprint: String?
    @State private var pending = false
    @State private var submissionError: String?

    private var companyOptions: [FreightClaimLifecycleWriteCanon.CompanyOption] {
        FreightClaimLifecycleWriteCanon.companies(for: claim)
    }

    private var validationMessage: String? {
        if requiresCompanySelection && selectedCompanyId == nil {
            return companyOptions.isEmpty
                ? "The claim response did not include a selectable claimant or respondent company."
                : "Select the company that owns this asset record."
        }
        guard assetType != nil else { return "Select an asset type." }
        guard FreightClaimLifecycleWriteCanon.clean(identifier) != nil else {
            return "Enter the asset identifier exactly as recorded on the source."
        }
        guard FreightClaimLifecycleWriteCanon.quantity(quantity, unit: quantityUnit) != nil else {
            return "Quantity and unit must be supplied together, and quantity cannot be negative."
        }
        guard let provenance else { return "Select the asset provenance." }
        if provenance.requiresSourceProvider,
           FreightClaimLifecycleWriteCanon.clean(sourceProvider) == nil {
            return "Connected integration evidence requires the provider name."
        }
        if provenance.requiresSourceReference,
           FreightClaimLifecycleWriteCanon.clean(sourceReference) == nil {
            return "This provenance requires a source reference."
        }
        if provenance.requiresObservedAt && !hasObservedAt {
            return "This external record requires an explicit observation time."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let submissionError {
                    Section("Not confirmed") {
                        Text(submissionError)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if requiresCompanySelection {
                    Section("Record owner") {
                        Picker("Company", selection: $selectedCompanyId) {
                            Text("Select company").tag(nil as Int?)
                            ForEach(companyOptions) { option in
                                Text(option.label).tag(Optional(option.id))
                            }
                        }
                    }
                }

                Section("Typed asset") {
                    Picker("Asset type", selection: $assetType) {
                        Text("Select asset type").tag(nil as FreightClaimsAPI.ClaimAssetType?)
                        ForEach(FreightClaimLifecycleWriteCanon.assetTypes(for: mode)) { type in
                            Text(type.label).tag(Optional(type))
                        }
                    }
                    TextField("Identifier", text: $identifier)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Quantity (optional)", text: $quantity)
                        .keyboardType(.decimalPad)
                    TextField("Quantity unit (optional)", text: $quantityUnit)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section("Provenance") {
                    Picker("Source", selection: $provenance) {
                        Text("Select provenance").tag(nil as FreightClaimsAPI.ClaimAssetProvenance?)
                        ForEach(FreightClaimsAPI.ClaimAssetProvenance.allCases) { source in
                            Text(source.label).tag(Optional(source))
                        }
                    }
                    if provenance?.requiresSourceProvider == true {
                        TextField("Provider", text: $sourceProvider)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if provenance?.requiresSourceReference == true {
                        TextField("Source reference", text: $sourceReference)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if provenance?.requiresObservedAt == true {
                        Toggle("Observation time recorded", isOn: $hasObservedAt)
                        if hasObservedAt {
                            DatePicker(
                                "Observed at",
                                selection: $observedAt,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }
                }

                Section {
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if pending { ProgressView().controlSize(.small) }
                            Text(pending ? "Confirming record" : "Record asset")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(validationMessage != nil || pending)
                } footer: {
                    Text("The asset is shown only after a matching typed record is read back from the claim ledger.")
                }
            }
            .navigationTitle("Claim asset")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(pending)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(pending)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard !pending,
              validationMessage == nil,
              let assetType,
              let provenance,
              let identifier = FreightClaimLifecycleWriteCanon.clean(identifier),
              let parsedQuantity = FreightClaimLifecycleWriteCanon.quantity(quantity, unit: quantityUnit) else {
            return
        }
        let provider = provenance.requiresSourceProvider
            ? FreightClaimLifecycleWriteCanon.clean(sourceProvider)
            : nil
        let reference = provenance.requiresSourceReference
            ? FreightClaimLifecycleWriteCanon.clean(sourceReference)
            : nil
        let observation = provenance.requiresObservedAt && hasObservedAt ? observedAt : nil
        let companyId = requiresCompanySelection ? selectedCompanyId : nil
        let fingerprint = [
            claim.claimId,
            companyId.map { String($0) } ?? "",
            assetType.rawValue,
            identifier,
            parsedQuantity.value.map { String($0) } ?? "",
            parsedQuantity.unit ?? "",
            provenance.rawValue,
            provider ?? "",
            reference ?? "",
            observation.map { String($0.timeIntervalSince1970) } ?? "",
        ].joined(separator: "|")
        let stableRequestKey: UUID
        if requestFingerprint == fingerprint, let requestKey {
            stableRequestKey = requestKey
        } else {
            stableRequestKey = UUID()
            requestKey = stableRequestKey
            requestFingerprint = fingerprint
        }

        pending = true
        submissionError = nil
        defer { pending = false }

        do {
            let result = try await EusoTripAPI.shared.freightClaims.recordClaimAsset(
                claimId: claim.claimId,
                companyId: companyId,
                assetType: assetType,
                identifier: identifier,
                quantity: parsedQuantity.value,
                quantityUnit: parsedQuantity.unit,
                provenanceSource: provenance,
                sourceProvider: provider,
                sourceReference: reference,
                observedAt: observation,
                requestKey: stableRequestKey
            )
            guard result.claimId == claim.claimId,
                  result.transportMode == mode,
                  result.assetType == assetType,
                  result.identifier == identifier,
                  result.companyId == (companyId ?? result.companyId),
                  FreightClaimLifecycleWriteCanon.quantitiesMatch(result.quantity, parsedQuantity.value),
                  result.quantityUnit == parsedQuantity.unit,
                  result.provenanceSource == provenance,
                  result.sourceProvider == provider,
                  result.sourceReference == reference,
                  FreightClaimLifecycleWriteCanon.datesMatch(result.observedAt, observation),
                  result.verificationStatus == "unverified",
                  result.referenceNumber == FreightClaimConsumerCanon.clean(claim.load.referenceNumber) else {
                submissionError = "EusoTrip returned an acknowledgement that does not match this asset draft. The same request identity is retained for retry."
                return
            }
            guard let refreshed = try await FreightClaimConsumerCanon.detail(claimId: claim.claimId, mode: mode),
                  refreshed.assetLedger.state == "recorded",
                  refreshed.assetLedger.accessState == "granted",
                  refreshed.assetLedger.trackingState == "tracked",
                  refreshed.assetLedger.provenance.source == "freight_claim_assets",
                  let persisted = refreshed.assetLedger.records.first(where: { $0.id == result.id }),
                  persisted.companyId == result.companyId,
                  persisted.assetType == assetType.rawValue,
                  persisted.identifier == identifier,
                  FreightClaimLifecycleWriteCanon.quantitiesMatch(persisted.quantity, parsedQuantity.value),
                  persisted.quantityUnit == parsedQuantity.unit,
                  persisted.provenanceSource == provenance.rawValue,
                  persisted.sourceProvider == provider,
                  persisted.sourceReference == reference,
                  FreightClaimLifecycleWriteCanon.datesMatch(persisted.observedAt, observation),
                  persisted.verificationStatus == "unverified" else {
                submissionError = "The asset was acknowledged, but its matching typed row is not yet present in the refreshed claim ledger. The same request identity is retained for retry."
                return
            }
            requestKey = nil
            requestFingerprint = nil
            onConfirmed(refreshed)
            dismiss()
        } catch {
            submissionError = "The asset is not confirmed. \(FreightClaimConsumerCanon.errorMessage(error)) The same request identity is retained for retry."
        }
    }
}

private struct FreightClaimDeadlineRecordForm: View {
    @Environment(\.dismiss) private var dismiss
    let claim: FreightClaimsAPI.ClaimDetail
    let mode: FreightClaimsAPI.TransportMode
    let requiresCompanySelection: Bool
    let onConfirmed: (FreightClaimsAPI.ClaimDetail) -> Void

    @State private var selectedCompanyId: Int?
    @State private var deadlineType: FreightClaimsAPI.ClaimDeadlineType?
    @State private var hasDueAt = false
    @State private var dueAt = Date()
    @State private var jurisdictionCode = ""
    @State private var authorityType: FreightClaimsAPI.ClaimDeadlineAuthority?
    @State private var authorityCitation = ""
    @State private var sourceURI = ""
    @State private var sourceReference = ""
    @State private var ruleVersion = ""
    @State private var requestKey: UUID?
    @State private var requestFingerprint: String?
    @State private var pending = false
    @State private var submissionError: String?

    private var companyOptions: [FreightClaimLifecycleWriteCanon.CompanyOption] {
        FreightClaimLifecycleWriteCanon.companies(for: claim)
    }

    private var normalizedSourceURI: String? {
        FreightClaimLifecycleWriteCanon.clean(sourceURI)
    }

    private var validationMessage: String? {
        if requiresCompanySelection && selectedCompanyId == nil {
            return companyOptions.isEmpty
                ? "The claim response did not include a selectable claimant or respondent company."
                : "Select the company that owns this deadline record."
        }
        guard deadlineType != nil else { return "Select a deadline type." }
        guard hasDueAt else { return "Confirm the recorded due date and time." }
        guard let authorityType else { return "Select the governing authority type." }
        if authorityType.requiresCitation,
           FreightClaimLifecycleWriteCanon.clean(authorityCitation) == nil {
            return "This authority type requires the exact governing citation."
        }
        guard FreightClaimLifecycleWriteCanon.validSourceURI(normalizedSourceURI) else {
            return "Source URL must be a complete HTTP or HTTPS address."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let submissionError {
                    Section("Not confirmed") {
                        Text(submissionError)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if requiresCompanySelection {
                    Section("Record owner") {
                        Picker("Company", selection: $selectedCompanyId) {
                            Text("Select company").tag(nil as Int?)
                            ForEach(companyOptions) { option in
                                Text(option.label).tag(Optional(option.id))
                            }
                        }
                    }
                }

                Section("Deadline") {
                    Picker("Deadline type", selection: $deadlineType) {
                        Text("Select deadline type").tag(nil as FreightClaimsAPI.ClaimDeadlineType?)
                        ForEach(FreightClaimsAPI.ClaimDeadlineType.allCases) { type in
                            Text(type.label).tag(Optional(type))
                        }
                    }
                    Toggle("Due date and time recorded", isOn: $hasDueAt)
                    if hasDueAt {
                        DatePicker(
                            "Due at",
                            selection: $dueAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    TextField("Jurisdiction code (optional)", text: $jurisdictionCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section("Authority") {
                    Picker("Authority type", selection: $authorityType) {
                        Text("Select authority type").tag(nil as FreightClaimsAPI.ClaimDeadlineAuthority?)
                        ForEach(FreightClaimsAPI.ClaimDeadlineAuthority.allCases) { authority in
                            Text(authority.label).tag(Optional(authority))
                        }
                    }
                    if authorityType?.requiresCitation == true {
                        TextField("Authority citation", text: $authorityCitation)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()
                    }
                    TextField("Source URL (optional)", text: $sourceURI)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Source reference (optional)", text: $sourceReference)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Rule version (optional)", text: $ruleVersion)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if pending { ProgressView().controlSize(.small) }
                            Text(pending ? "Confirming deadline" : "Record deadline")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(validationMessage != nil || pending)
                } footer: {
                    Text("The deadline is shown only after its authority and due time are read back from the claim ledger.")
                }
            }
            .navigationTitle("Claim deadline")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(pending)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(pending)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard !pending,
              validationMessage == nil,
              let deadlineType,
              let authorityType else { return }
        let companyId = requiresCompanySelection ? selectedCompanyId : nil
        let jurisdiction = FreightClaimLifecycleWriteCanon.clean(jurisdictionCode)?.uppercased()
        let citation = authorityType.requiresCitation
            ? FreightClaimLifecycleWriteCanon.clean(authorityCitation)
            : nil
        let sourceURI = normalizedSourceURI
        let reference = FreightClaimLifecycleWriteCanon.clean(sourceReference)
        let version = FreightClaimLifecycleWriteCanon.clean(ruleVersion)
        let fingerprint = [
            claim.claimId,
            companyId.map { String($0) } ?? "",
            deadlineType.rawValue,
            String(dueAt.timeIntervalSince1970),
            jurisdiction ?? "",
            authorityType.rawValue,
            citation ?? "",
            sourceURI ?? "",
            reference ?? "",
            version ?? "",
        ].joined(separator: "|")
        let stableRequestKey: UUID
        if requestFingerprint == fingerprint, let requestKey {
            stableRequestKey = requestKey
        } else {
            stableRequestKey = UUID()
            requestKey = stableRequestKey
            requestFingerprint = fingerprint
        }

        pending = true
        submissionError = nil
        defer { pending = false }

        do {
            let result = try await EusoTripAPI.shared.freightClaims.recordClaimDeadline(
                claimId: claim.claimId,
                companyId: companyId,
                deadlineType: deadlineType,
                dueAt: dueAt,
                jurisdictionCode: jurisdiction,
                authorityType: authorityType,
                authorityCitation: citation,
                sourceUri: sourceURI,
                sourceReference: reference,
                ruleVersion: version,
                requestKey: stableRequestKey
            )
            guard result.claimId == claim.claimId,
                  result.transportMode == mode,
                  result.companyId == (companyId ?? result.companyId),
                  result.deadlineType == deadlineType,
                  FreightClaimLifecycleWriteCanon.datesMatch(result.dueAt, dueAt),
                  result.jurisdictionCode == jurisdiction,
                  result.authorityType == authorityType,
                  result.authorityCitation == citation,
                  result.sourceUri == sourceURI,
                  result.sourceReference == reference,
                  result.ruleVersion == version,
                  result.authorityStatus == "entered",
                  result.status == "open",
                  result.referenceNumber == FreightClaimConsumerCanon.clean(claim.load.referenceNumber) else {
                submissionError = "EusoTrip returned an acknowledgement that does not match this deadline draft. The same request identity is retained for retry."
                return
            }
            guard let refreshed = try await FreightClaimConsumerCanon.detail(claimId: claim.claimId, mode: mode),
                  refreshed.deadlineLedger.state == "recorded",
                  refreshed.deadlineLedger.accessState == "granted",
                  refreshed.deadlineLedger.trackingState == "tracked",
                  refreshed.deadlineLedger.provenance.source == "freight_claim_deadlines",
                  let persisted = refreshed.deadlineLedger.records.first(where: { $0.id == result.id }),
                  persisted.companyId == result.companyId,
                  persisted.deadlineType == deadlineType.rawValue,
                  FreightClaimLifecycleWriteCanon.datesMatch(persisted.dueAt, dueAt),
                  persisted.jurisdictionCode == jurisdiction,
                  persisted.authorityType == authorityType.rawValue,
                  persisted.authorityCitation == citation,
                  persisted.sourceUri == sourceURI,
                  persisted.sourceReference == reference,
                  persisted.ruleVersion == version,
                  persisted.authorityStatus == "entered",
                  persisted.status == "open" else {
                submissionError = "The deadline was acknowledged, but its matching authority row is not yet present in the refreshed claim ledger. The same request identity is retained for retry."
                return
            }
            requestKey = nil
            requestFingerprint = nil
            onConfirmed(refreshed)
            dismiss()
        } catch {
            submissionError = "The deadline is not confirmed. \(FreightClaimConsumerCanon.errorMessage(error)) The same request identity is retained for retry."
        }
    }
}

private struct FreightClaimReserveRecordForm: View {
    @Environment(\.dismiss) private var dismiss
    let claim: FreightClaimsAPI.ClaimDetail
    let mode: FreightClaimsAPI.TransportMode
    let onConfirmed: (FreightClaimsAPI.ClaimDetail) -> Void

    @State private var amount = ""
    @State private var status: FreightClaimsAPI.ClaimReserveStatus?
    @State private var basis = ""
    @State private var requestKey: UUID?
    @State private var requestFingerprint: String?
    @State private var pending = false
    @State private var submissionError: String?

    private var normalizedBasis: String? {
        FreightClaimLifecycleWriteCanon.clean(basis)
    }

    private var validationMessage: String? {
        guard claim.currency != nil else {
            return "The locked transaction currency is unavailable. No reserve can be recorded from this screen."
        }
        guard let amount = FreightClaimLifecycleWriteCanon.reserveAmount(amount) else {
            return "Enter a nonnegative reserve amount with no more than two decimal places."
        }
        guard let status else { return "Select the reserve status." }
        if status == .released && amount != 0 {
            return "A released reserve must have an explicit zero balance."
        }
        guard let basis = normalizedBasis, (10...5_000).contains(basis.count) else {
            return "Enter a decision basis between 10 and 5,000 characters."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let submissionError {
                    Section("Not confirmed") {
                        Text(submissionError)
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Versioned reserve") {
                    FreightClaimValueRow(
                        label: "Locked currency",
                        value: claim.currency?.rawValue
                    )
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Status", selection: $status) {
                        Text("Select reserve status").tag(nil as FreightClaimsAPI.ClaimReserveStatus?)
                        ForEach(FreightClaimsAPI.ClaimReserveStatus.allCases) { reserveStatus in
                            Text(reserveStatus.label).tag(Optional(reserveStatus))
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Decision basis")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $basis)
                            .frame(minHeight: 100)
                            .accessibilityLabel("Reserve decision basis")
                    }
                }

                Section {
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if pending { ProgressView().controlSize(.small) }
                            Text(pending ? "Confirming reserve" : "Set reserve")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(validationMessage != nil || pending)
                } footer: {
                    Text("A new reserve supersedes the prior active version. It is shown only after the authorized reserve ledger returns the exact amount, currency, status, and basis.")
                }
            }
            .navigationTitle("Claim reserve")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(pending)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(pending)
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard !pending,
              validationMessage == nil,
              let amount = FreightClaimLifecycleWriteCanon.reserveAmount(amount),
              let currency = claim.currency,
              let status,
              let basis = normalizedBasis else { return }
        let fingerprint = [
            claim.claimId,
            String(amount),
            currency.rawValue,
            status.rawValue,
            basis,
        ].joined(separator: "|")
        let stableRequestKey: UUID
        if requestFingerprint == fingerprint, let requestKey {
            stableRequestKey = requestKey
        } else {
            stableRequestKey = UUID()
            requestKey = stableRequestKey
            requestFingerprint = fingerprint
        }

        pending = true
        submissionError = nil
        defer { pending = false }

        do {
            let result = try await EusoTripAPI.shared.freightClaims.setClaimReserve(
                claimId: claim.claimId,
                amount: amount,
                currency: currency,
                status: status,
                basis: basis,
                requestKey: stableRequestKey
            )
            guard result.claimId == claim.claimId,
                  result.transportMode == mode,
                  FreightClaimLifecycleWriteCanon.quantitiesMatch(result.amount, amount),
                  result.currency == currency,
                  result.status == status,
                  result.basis == basis,
                  result.referenceNumber == FreightClaimConsumerCanon.clean(claim.load.referenceNumber),
                  result.version > 0 else {
                submissionError = "EusoTrip returned an acknowledgement that does not match this reserve decision. The same request identity is retained for retry."
                return
            }
            guard let refreshed = try await FreightClaimConsumerCanon.detail(claimId: claim.claimId, mode: mode),
                  refreshed.reserveLedger.state == "recorded",
                  refreshed.reserveLedger.accessState == "granted",
                  refreshed.reserveLedger.trackingState == "tracked",
                  refreshed.reserveLedger.provenance.source == "freight_claim_reserves",
                  let persisted = refreshed.reserveLedger.records?.first(where: { $0.id == result.id }),
                  persisted.version == result.version,
                  FreightClaimLifecycleWriteCanon.quantitiesMatch(persisted.amount, amount),
                  persisted.currency == currency.rawValue,
                  persisted.status == status.rawValue,
                  persisted.basis == basis else {
                submissionError = "The reserve was acknowledged, but its matching financial version is not present in the refreshed authorized ledger. The same request identity is retained for retry."
                return
            }
            requestKey = nil
            requestFingerprint = nil
            onConfirmed(refreshed)
            dismiss()
        } catch {
            submissionError = "The reserve is not confirmed. \(FreightClaimConsumerCanon.errorMessage(error)) The same request identity is retained for retry."
        }
    }
}

struct RailCargoClaimScreen: View {
    let theme: Theme.Palette
    var claimId: String

    init(theme: Theme.Palette, claimId: String = "") {
        self.theme = theme
        self.claimId = claimId
    }

    var body: some View {
        Shell(theme: theme) {
            RailCargoClaimBody(claimId: claimId)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)
                ],
                trailing: [
                    NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: false)
                ],
                orbState: .idle
            )
        }
    }
}

private struct RailCargoClaimBody: View {
    @Environment(\.palette) private var palette
    let claimId: String

    @State private var claim: FreightClaimsAPI.ClaimDetail?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            FreightClaimSurfaceHeader(
                context: "Rail cargo claim",
                title: "Claim case file",
                purpose: "Inspect the claim tied to one rail shipment and verify its parties, exposure, evidence, and recorded progress."
            )

            if loading && claim == nil {
                ProgressView("Loading claim")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let loadError {
                LifecycleCard(accentDanger: true) {
                    Text(loadError)
                        .font(.body)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let claim {
                identity(for: claim)
                transaction(for: claim)
                if claim.type?.lowercased() == FreightClaimsAPI.ClaimType.shortage.rawValue {
                    shortageGap
                }
                parties(for: claim)
                FreightClaimEvidenceRegister(evidence: claim.evidence)
                FreightClaimWorkflowRegister(workflow: claim.workflow)
                provenance(for: claim)
            } else {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No rail cargo claims",
                    subtitle: "No claim tied to a rail shipment is available to this account."
                )
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private func identity(for claim: FreightClaimsAPI.ClaimDetail) -> some View {
        LifecycleCard {
            VStack(spacing: 0) {
                FreightClaimValueRow(label: "Claim", value: FreightClaimConsumerCanon.clean(claim.claimNumber))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Rail shipment", value: FreightClaimConsumerCanon.reference(for: claim, mode: .rail))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Type", value: FreightClaimConsumerCanon.label(claim.type))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Status", value: FreightClaimConsumerCanon.label(claim.status))
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Claimed exposure",
                    value: FreightClaimConsumerCanon.financialContext(amount: claim.amount, currency: claim.currency)
                )
            }
        }
    }

    private func transaction(for claim: FreightClaimsAPI.ClaimDetail) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Shipment context")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.bottom, Space.s2)
                FreightClaimValueRow(label: "Origin", value: FreightClaimConsumerCanon.clean(claim.load.origin))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Destination", value: FreightClaimConsumerCanon.clean(claim.load.destination))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Commodity", value: FreightClaimConsumerCanon.clean(claim.load.commodity))
                Divider().opacity(0.25)
                FreightClaimValueRow(
                    label: "Recorded quantity",
                    value: FreightClaimConsumerCanon.quantityContext(amount: claim.load.weight, unit: claim.load.weightUnit)
                )
            }
        }
    }

    private var shortageGap: some View {
        LifecycleCard(accentDanger: true) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Label("Shortage quantities unavailable", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(Brand.danger)
                Text("This claim does not carry typed expected quantity, received quantity, and quantity unit evidence. The app will not infer those values from shipment weight or narrative text.")
                    .font(.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func parties(for claim: FreightClaimsAPI.ClaimDetail) -> some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Claim parties")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.bottom, Space.s2)
                FreightClaimValueRow(label: "Claimant", value: FreightClaimConsumerCanon.clean(claim.claimant?.name))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Respondent", value: FreightClaimConsumerCanon.clean(claim.respondent?.name))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Rail carrier", value: FreightClaimConsumerCanon.clean(claim.carrier?.name))
                Divider().opacity(0.25)
                FreightClaimValueRow(label: "Shipper", value: FreightClaimConsumerCanon.clean(claim.shipper?.name))
            }
        }
    }

    private func provenance(for claim: FreightClaimsAPI.ClaimDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Record provenance")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            FreightClaimValueRow(label: "Filed", value: FreightClaimConsumerCanon.clean(claim.filedDate))
            FreightClaimValueRow(label: "Last updated", value: FreightClaimConsumerCanon.clean(claim.updatedAt))
            Text("Source: EusoTrip freight claims register")
                .font(.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .contain)
    }

    @MainActor
    private func load() async {
        loading = claim == nil
        loadError = nil
        do {
            claim = try await FreightClaimConsumerCanon.detail(claimId: claimId, mode: .rail)
        } catch {
            loadError = FreightClaimConsumerCanon.errorMessage(error)
        }
        loading = false
    }
}

#Preview("Rail cargo claim") {
    RailCargoClaimScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
