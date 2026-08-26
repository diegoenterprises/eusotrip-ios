//
//  686_RailSTCCCommodityValidation.swift
//  EusoTrip - Rail shipper STCC evidence validation.
//
//  The screen validates user-supplied STCC entries against the tenant-visible,
//  versioned product evidence registry. Syntax alone never becomes an
//  operational approval, and an HS/HTS value is shown only when it belongs to
//  the exact matched product profile.
//

import SwiftUI

struct RailSTCCCommodityValidationScreen: View {
    let theme: Theme.Palette
    let initialCodes: [String]

    init(
        theme: Theme.Palette = Theme.dark,
        initialCodes: [String] = []
    ) {
        self.theme = theme
        self.initialCodes = initialCodes
    }

    var body: some View {
        Shell(theme: theme) {
            RailSTCCValidationBody(initialCodes: initialCodes)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house.fill", isCurrent: false),
                    NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                ],
                trailing: [
                    NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                    NavSlot(label: "Me", systemImage: "person.fill", isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

private struct STCCValidationLine686: Identifiable {
    let id = UUID()
    let ordinal: Int
    let result: CommodityLookupAPI.StccValidationResponse
}

private struct RailSTCCValidationBody: View {
    @Environment(\.palette) private var palette

    @State private var inputText: String
    @State private var lines: [STCCValidationLine686] = []
    @State private var batch: CommodityLookupAPI.StccBatchValidationResponse?
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var didValidateInitialCodes = false

    init(initialCodes: [String]) {
        _inputText = State(initialValue: initialCodes.joined(separator: "\n"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                inputWell
                commandRail
                if isValidating {
                    progressRegister
                } else if let errorMessage {
                    errorRegister(errorMessage)
                } else if lines.isEmpty {
                    emptyRegister
                } else {
                    resultSummary
                    ForEach(lines) { line in
                        resultRegister(line)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s2)
        }
        .background(palette.bgPage)
        .task {
            guard !didValidateInitialCodes, !parsedCodes.isEmpty else { return }
            didValidateInitialCodes = true
            await validate()
        }
        .eusoRefreshable {
            guard !parsedCodes.isEmpty else { return }
            await validate()
        }
        .onChange(of: inputText) { _, _ in
            lines = []
            batch = nil
            errorMessage = nil
        }
    }

    private var parsedCodes: [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",;"))
        return inputText
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canValidate: Bool {
        !isValidating && (1...100).contains(parsedCodes.count)
    }

    private var verifiedCount: Int {
        lines.filter { $0.result.isDecisionEligible }.count
    }

    private var issueCount: Int {
        max(0, lines.count - verifiedCount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s2) {
                EusoTripEyebrow(verbatim: "SHIPPER · RAIL · COMMODITY EVIDENCE")
                    .font(EType.micro)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("STCC")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Validate commodity codes")
                .font(EType.h1)
                .foregroundStyle(palette.textPrimary)
            Text("Registry identity, evidence status, source, and freshness remain attached to every result.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            IridescentHairline()
        }
    }

    private var inputWell: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("STCC ENTRIES")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(parsedCodes.count) / 100")
                    .font(EType.mono(.micro))
                    .foregroundStyle(parsedCodes.count > 100 ? Brand.danger : palette.textTertiary)
            }

            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("7-digit STCC entries")
                        .font(EType.body)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $inputText)
                    .font(EType.mono(.body))
                    .foregroundStyle(palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .frame(minHeight: 112)
                    .accessibilityLabel("STCC entries")
            }
            .padding(Space.s3)
            .background(palette.bgCardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(parsedCodes.count > 100 ? Brand.danger : palette.borderSoft)
            )

            if parsedCodes.count > 100 {
                Text("The registry validates at most 100 entries in one request.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private var commandRail: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await validate() }
            } label: {
                Label(isValidating ? "Validating" : "Validate", systemImage: "checkmark.shield")
                    .font(EType.bodyStrong)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canValidate)
            .opacity(canValidate ? 1 : 0.45)

            Button {
                inputText = ""
                lines = []
                batch = nil
                errorMessage = nil
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(palette.textSecondary)
                    .background(palette.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isValidating)
            .accessibilityLabel("Clear STCC entries")
        }
    }

    private var progressRegister: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Reading the evidence registry")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorRegister(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.body)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.7))
        )
    }

    private var emptyRegister: some View {
        EusoEmptyState(
            systemImage: "shippingbox.and.arrow.backward",
            title: "No STCC validation yet",
            subtitle: "Validated registry evidence appears here after entries are submitted."
        )
    }

    private var resultSummary: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("VALIDATION REGISTER")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(verifiedCount) verified · \(issueCount) review")
                    .font(EType.mono(.caption))
                    .foregroundStyle(issueCount == 0 ? Brand.success : Brand.warning)
            }
            if let reason = batch?.unavailableReason, !reason.isEmpty {
                Text(reason)
                    .font(EType.caption)
                    .foregroundStyle(issueCount == 0 ? palette.textSecondary : Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resultRegister(_ line: STCCValidationLine686) -> some View {
        let result = line.result
        let verified = result.isDecisionEligible
        let tint = verified ? Brand.success : Brand.warning
        let match = result.matched

        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(result.stcc.isEmpty ? "No code" : result.stcc)
                        .font(EType.mono(.body))
                        .foregroundStyle(palette.textPrimary)
                    Text(statusLabel(for: result))
                        .font(EType.micro)
                        .foregroundStyle(tint)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }

            if let match {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(match.name)
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    identityRow(label: "STCC", value: match.stccCode ?? result.stcc)
                    identityRow(label: "HS / HTS", value: match.hsCode ?? "Not recorded")
                    identityRow(label: "UN", value: match.unNumber ?? "Not recorded")
                    identityRow(label: "Dangerous goods", value: dangerousGoodsLabel(match.hazmatLinked))
                }

                IridescentHairline()

                VStack(alignment: .leading, spacing: Space.s1) {
                    proofRow(label: "Source", value: match.sourceName ?? match.sourceKey ?? "Unavailable")
                    proofRow(label: "Evidence", value: evidenceLabel(match))
                    proofRow(label: "Retrieved", value: displayTimestamp(match.evidenceRetrievedAt) ?? "Unknown")
                    proofRow(label: "Freshness", value: freshnessLabel(match.freshnessState))
                }
            }

            if let reason = result.unavailableReason, !reason.isEmpty {
                Text(reason)
                    .font(EType.caption)
                    .foregroundStyle(verified ? palette.textSecondary : Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(tint.opacity(verified ? 0.45 : 0.7))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: line))
    }

    private func identityRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func proofRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(label.uppercased())
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusLabel(for result: CommodityLookupAPI.StccValidationResponse) -> String {
        if result.isDecisionEligible { return "EVIDENCE VERIFIED" }
        if !result.formatValid { return "INVALID FORMAT" }
        if !result.contractVerified { return "CONTRACT UNAVAILABLE" }
        if result.matched == nil { return "NO REGISTRY MATCH" }
        return "EVIDENCE REVIEW REQUIRED"
    }

    private func dangerousGoodsLabel(_ linked: Bool?) -> String {
        switch linked {
        case true: return "Linked"
        case false: return "Not linked"
        case nil: return "Unknown"
        }
    }

    private func evidenceLabel(_ match: CommodityLookupAPI.CommodityHit) -> String {
        let id = match.evidenceId.map(String.init) ?? "unknown"
        let version = match.profileVersion.map(String.init) ?? "unknown"
        return "#\(id) · profile v\(version)"
    }

    private func freshnessLabel(_ state: String?) -> String {
        switch state {
        case "current": return "Current"
        case "no_declared_refresh_policy": return "No declared refresh cadence"
        case "stale": return "Stale"
        case "unknown", nil: return "Unknown"
        default: return state ?? "Unknown"
        }
    }

    private func displayTimestamp(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func accessibilityLabel(for line: STCCValidationLine686) -> String {
        let result = line.result
        let name = result.matched?.name ?? "No evidence-backed product"
        let reason = result.unavailableReason ?? ""
        return "Entry \(line.ordinal), STCC \(result.stcc), \(statusLabel(for: result)), \(name). \(reason)"
    }

    @MainActor
    private func validate() async {
        guard !isValidating else { return }
        let codes = parsedCodes
        guard (1...100).contains(codes.count) else {
            errorMessage = codes.isEmpty
                ? "Enter at least one STCC code."
                : "Validate no more than 100 STCC entries at once."
            return
        }

        isValidating = true
        errorMessage = nil
        lines = []
        batch = nil
        defer { isValidating = false }

        do {
            let response = try await EusoTripAPI.shared.commodity.validateStccs(codes)
            guard response.contractVerified, response.results.count == codes.count else {
                throw EusoTripAPIError.trpcError(
                    "The STCC evidence response could not be verified. No entries were accepted."
                )
            }
            batch = response
            lines = response.results.enumerated().map { index, result in
                STCCValidationLine686(ordinal: index + 1, result: result)
            }
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

#Preview("686 · Rail STCC Validation · Night") {
    RailSTCCCommodityValidationScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("686 · Rail STCC Validation · Light") {
    RailSTCCCommodityValidationScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
