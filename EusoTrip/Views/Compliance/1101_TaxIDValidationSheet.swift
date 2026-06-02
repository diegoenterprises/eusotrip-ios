//
//  1101_TaxIDValidationSheet.swift
//  EusoTrip — Compliance · RIOS §11 · Tax-ID + Address validation sheet.
//
//  Presented as `.sheet` content (capture/confirm precedent, 1100-1110).
//  Drives kyc.matchTaxId + kyc.runAddressValidation and renders the server
//  status VERBATIM — green only on an explicit valid:true / verified:true,
//  a neutral "validator unavailable — review" (Brand.warning) on null, and
//  red on an explicit false. No fabricated success.
//

import SwiftUI

struct TaxIDValidationSheet: View {
    /// Optional entity the validation should be attributed to server-side.
    var userId: Int? = nil
    /// Called with the resolved tax-id result when the operator dismisses
    /// after a successful run, so the presenting wizard (1111) can advance
    /// its gate. Optional — the sheet is fully usable standalone.
    var onResolved: ((KycAPI.TaxIdResult, KycAPI.AddressResult?) -> Void)? = nil

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    // MARK: Country

    /// US/CA/MX with the per-country registry label + format hint.
    private enum TaxCountry: String, CaseIterable, Identifiable {
        case us = "US", ca = "CA", mx = "MX"
        var id: String { rawValue }
        var flag: String {
            switch self { case .us: return "🇺🇸"; case .ca: return "🇨🇦"; case .mx: return "🇲🇽" }
        }
        var name: String {
            switch self { case .us: return "United States"; case .ca: return "Canada"; case .mx: return "Mexico" }
        }
        /// Registry identifier label shown on the tax-id field.
        var taxLabel: String {
            switch self { case .us: return "EIN"; case .ca: return "BN"; case .mx: return "RFC" }
        }
        var taxPlaceholder: String {
            switch self {
            case .us: return "12-3456789"
            case .ca: return "123456789RT0001"
            case .mx: return "ABC123456XYZ"
            }
        }
        var postalLabel: String {
            switch self { case .us: return "ZIP code"; case .ca: return "Postal code"; case .mx: return "C.P." }
        }
        var stateLabel: String {
            switch self { case .us: return "State"; case .ca: return "Province"; case .mx: return "Estado" }
        }
        var taxKeyboard: UIKeyboardType {
            // CA business numbers + MX RFC are alphanumeric; US EIN is numeric.
            self == .us ? .numbersAndPunctuation : .asciiCapable
        }
    }

    // MARK: Inputs

    @State private var country: TaxCountry = .us
    @State private var taxId = ""
    @State private var legalName = ""
    @State private var line1 = ""
    @State private var city = ""
    @State private var stateRegion = ""
    @State private var postal = ""

    // MARK: Run state

    @State private var running = false
    @State private var runError: String? = nil
    @State private var taxResult: KycAPI.TaxIdResult? = nil
    @State private var addressResult: KycAPI.AddressResult? = nil
    /// True once a run has completed (so we don't show result cards before
    /// the operator has submitted anything).
    @State private var didRun = false

    private var canRun: Bool {
        !taxId.trimmingCharacters(in: .whitespaces).isEmpty && !running
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    header
                    countryPicker
                    taxSection
                    addressSection
                    if let runError {
                        errorBanner(runError)
                    }
                    if didRun {
                        resultsSection
                    }
                    runButton
                    Color.clear.frame(height: Space.s6)
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Tax-ID validation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismissResolved() }
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .environment(\.palette, palette)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE · KYB §11")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Validate the registry tax ID and operating address against the relevant government source.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Country picker

    private var countryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COUNTRY OF REGISTRATION")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(TaxCountry.allCases) { c in
                    countryChip(c)
                }
            }
        }
    }

    @ViewBuilder
    private func countryChip(_ c: TaxCountry) -> some View {
        let selected = c == country
        Button {
            guard c != country else { return }
            country = c
            // Country switch invalidates any prior result — the registry
            // and field semantics changed under it.
            resetResults()
        } label: {
            VStack(spacing: 2) {
                Text(c.flag).font(.system(size: 20))
                Text(c.taxLabel)
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(selected ? .white : palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(selected ? AnyShapeStyle(LinearGradient.diagonal)
                                   : AnyShapeStyle(palette.bgCardSoft.opacity(0.9)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Color.clear : palette.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Tax-ID section

    private var taxSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel("\(country.taxLabel) · \(country.name)", icon: "number")
            GlassField(
                label: "\(country.taxLabel) (tax ID)",
                placeholder: country.taxPlaceholder,
                icon: "number",
                text: $taxId,
                keyboardType: country.taxKeyboard,
                autocapitalization: .characters
            )
            GlassField(
                label: "Legal name (optional)",
                placeholder: "Registered legal entity name",
                icon: "building.2",
                text: $legalName,
                autocapitalization: .words
            )
        }
        .padding(Space.s4)
        .eusoCard()
        .onChange(of: taxId) { _, _ in if didRun { resetResults() } }
        .onChange(of: legalName) { _, _ in if didRun { resetResults() } }
    }

    // MARK: Address section

    private var addressSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionLabel("Operating address", icon: "mappin.and.ellipse")
            GlassField(
                label: "Street address",
                placeholder: "Line 1",
                icon: "mappin",
                text: $line1,
                textContentType: .streetAddressLine1,
                autocapitalization: .words
            )
            HStack(spacing: Space.s2) {
                GlassField(
                    label: "City",
                    placeholder: "City",
                    icon: nil,
                    text: $city,
                    textContentType: .addressCity,
                    autocapitalization: .words
                )
                GlassField(
                    label: country.stateLabel,
                    placeholder: country.stateLabel,
                    icon: nil,
                    text: $stateRegion,
                    autocapitalization: .characters
                )
            }
            GlassField(
                label: country.postalLabel,
                placeholder: country.postalLabel,
                icon: nil,
                text: $postal,
                keyboardType: .asciiCapable,
                textContentType: .postalCode,
                autocapitalization: .characters
            )
            Text("Address validation runs only when a street line is provided.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .eusoCard()
        .onChange(of: line1) { _, _ in if didRun { resetResults() } }
    }

    // MARK: Results

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let taxResult {
                ValidationResultCard(
                    title: "\(country.taxLabel) registry match",
                    outcome: .forTaxId(taxResult.valid),
                    detail: taxResult.message,
                    normalized: taxResult.normalized,
                    source: taxResult.source
                )
            }
            if let addressResult {
                ValidationResultCard(
                    title: "Address verification",
                    outcome: .forVerified(addressResult.verified),
                    detail: nil,
                    normalized: nil,
                    source: addressResult.source
                )
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintDanger)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Run button

    private var runButton: some View {
        CTAButton(
            title: running ? "Validating…" : "Run validation",
            action: { Task { await runValidation() } },
            trailingIcon: running ? nil : "checkmark.shield",
            isLoading: !canRun || running
        )
    }

    // MARK: Shared label

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text(text.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Actions

    private func runValidation() async {
        let trimmedTax = taxId.trimmingCharacters(in: .whitespaces)
        guard !trimmedTax.isEmpty else { return }

        running = true
        runError = nil
        // Clear prior results so a partial failure can't leave a stale
        // "verified" card on screen.
        taxResult = nil
        addressResult = nil

        let trimmedName = legalName.trimmingCharacters(in: .whitespaces)
        let trimmedLine1 = line1.trimmingCharacters(in: .whitespaces)

        do {
            let tax = try await EusoTripAPI.shared.kyc.matchTaxId(
                taxId: trimmedTax,
                country: country.rawValue,
                legalName: trimmedName.isEmpty ? nil : trimmedName,
                userId: userId
            )
            taxResult = tax

            // Only run address validation when a street line was provided —
            // an empty line1 would just produce a meaningless null result.
            if !trimmedLine1.isEmpty {
                let addr = try await EusoTripAPI.shared.kyc.runAddressValidation(
                    line1: trimmedLine1,
                    city: city.trimmingCharacters(in: .whitespaces),
                    state: stateRegion.trimmingCharacters(in: .whitespaces),
                    postalCode: postal.trimmingCharacters(in: .whitespaces),
                    country: country.rawValue,
                    userId: userId
                )
                addressResult = addr
            }
            didRun = true
        } catch let apiErr as EusoTripAPIError {
            runError = apiErr.errorDescription ?? "Validation request failed. Try again."
        } catch let localized as LocalizedError {
            runError = localized.errorDescription ?? "Validation request failed. Try again."
        } catch {
            runError = error.localizedDescription
        }
        running = false
    }

    private func resetResults() {
        didRun = false
        taxResult = nil
        addressResult = nil
        runError = nil
    }

    private func dismissResolved() {
        if let taxResult { onResolved?(taxResult, addressResult) }
        dismiss()
    }
}

// MARK: - ValidationResultCard
//
// Renders ONE validation outcome honestly. The traffic-light state is
// derived strictly from the server's tri-state Bool? — never inferred —
// so a null (validator unconfigured / provider unavailable) reads as a
// neutral "needs review", not a fake pass.

private struct ValidationResultCard: View {
    enum Outcome {
        case verified           // explicit true  → green
        case rejected           // explicit false → red
        case unavailable        // null           → warning / manual review

        static func forTaxId(_ valid: Bool?) -> Outcome {
            switch valid { case .some(true): return .verified
                           case .some(false): return .rejected
                           case .none: return .unavailable }
        }
        static func forVerified(_ verified: Bool?) -> Outcome {
            switch verified { case .some(true): return .verified
                              case .some(false): return .rejected
                              case .none: return .unavailable }
        }
    }

    let title: String
    let outcome: Outcome
    let detail: String?
    let normalized: String?
    let source: String?

    @Environment(\.palette) private var palette

    private var tint: Color {
        switch outcome {
        case .verified:    return Brand.success
        case .rejected:    return Brand.danger
        case .unavailable: return Brand.warning
        }
    }
    private var icon: String {
        switch outcome {
        case .verified:    return "checkmark.seal.fill"
        case .rejected:    return "xmark.octagon.fill"
        case .unavailable: return "questionmark.circle.fill"
        }
    }
    private var label: String {
        switch outcome {
        case .verified:    return "Verified"
        case .rejected:    return "No match"
        case .unavailable: return "Validator unavailable — review"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(label)
                        .font(EType.caption)
                        .foregroundStyle(tint)
                }
                Spacer(minLength: 0)
            }

            if outcome == .unavailable {
                Text("The government registry validator did not return a confirmed result. This entity must be cleared by manual review before the gate clears.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail, !detail.isEmpty {
                metaRow("Message", detail)
            }
            if let normalized, !normalized.isEmpty {
                metaRow("Normalized", normalized, mono: true)
            }
            if let source, !source.isEmpty {
                metaRow("Source", source)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(tint.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func metaRow(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(k.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 84, alignment: .leading)
            Text(v)
                .font(mono ? EType.mono(.caption) : EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

#Preview("1101 · Tax-ID validation · Night") {
    Color.black
        .sheet(isPresented: .constant(true)) {
            TaxIDValidationSheet()
                .environment(\.palette, Theme.dark)
                .preferredColorScheme(.dark)
        }
}

#Preview("1101 · Tax-ID validation · Afternoon") {
    Color.white
        .sheet(isPresented: .constant(true)) {
            TaxIDValidationSheet()
                .environment(\.palette, Theme.light)
                .preferredColorScheme(.light)
        }
}
