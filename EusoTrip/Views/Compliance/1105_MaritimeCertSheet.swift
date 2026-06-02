//
//  1105_MaritimeCertSheet.swift
//  EusoTrip — RIOS §11 · Maritime certificate capture sheet.
//
//  Presented as .sheet content from the 1111 registration/compliance wizard
//  (capture-sheet precedent, 1100–1110). The crew member or company captures
//  a maritime credential — scan-to-autofill via CredentialScanCard (USCG MMC
//  / vessel docs), then confirm the structured fields — and the sheet calls
//  registration.attachMaritimeCert(...). Server status is rendered verbatim:
//  "verified"/"clear" reads green, everything else (pending /
//  provider_unavailable / null) reads as a neutral warning state. A lapse
//  banner surfaces when the entered expiry is near or past.
//

import SwiftUI

struct MaritimeCertSheet: View {
    /// Owner of the credential. The wizard passes the resolved entity id +
    /// whether it's a crew member ("crew") or the operating company
    /// ("company"). Defaulted so isolated previews / standalone presentation
    /// still construct, but the host wizard should always inject the real id.
    let ownerEntityId: Int
    var ownerEntityType: String = "crew"

    /// Fired with the server's AttachResult on a successful attach so the
    /// host wizard can advance its gate state. Optional — the sheet is fully
    /// usable without a host listening.
    var onAttached: ((RegistrationAPI.AttachResult) -> Void)? = nil

    /// Dismiss handle injected by the presenting sheet.
    var onClose: () -> Void = {}

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    // MARK: Form state
    @State private var certType: MaritimeCertType = .mmc
    @State private var ownerType: String = "crew"
    @State private var certNumber: String = ""
    @State private var issuer: String = ""
    @State private var vesselImoNumber: String = ""
    @State private var issuedAt: String = ""
    @State private var expiresAt: String = ""

    // MARK: Scan / submit state
    @State private var scanWarnings: [String] = []
    @State private var lowConfidenceFields: [String] = []
    @State private var submitting = false
    @State private var submitError: String? = nil
    @State private var result: RegistrationAPI.AttachResult? = nil

    /// Maritime credential taxonomy. Raw value is the server `certType` code;
    /// `.scanType` maps onto a credentialScanner type where one exists so the
    /// OCR card can pre-fill the form (MMC has a dedicated extractor; the
    /// vessel docs share the generic maritime path).
    enum MaritimeCertType: String, CaseIterable, Identifiable {
        case doc   = "DOC"     // Document of Compliance (ISM)
        case smc   = "SMC"     // Safety Management Certificate
        case issc  = "ISSC"    // International Ship Security Certificate
        case mmc   = "MMC"     // Merchant Mariner Credential (USCG)
        case stcw  = "STCW"    // Standards of Training, Certification & Watchkeeping
        case sire  = "SIRE"    // OCIMF vessel inspection
        case cdi    = "CDI"    // Chemical Distribution Institute
        case toe    = "TOE"    // Terminal Operations Endorsement
        case imdg   = "IMDG"   // Dangerous-goods carriage endorsement

        var id: String { rawValue }

        var label: String {
            switch self {
            case .doc:  return "DOC · Document of Compliance"
            case .smc:  return "SMC · Safety Management Cert"
            case .issc: return "ISSC · Ship Security Cert"
            case .mmc:  return "MMC · Merchant Mariner Credential"
            case .stcw: return "STCW · Training & Watchkeeping"
            case .sire: return "SIRE · Vessel Inspection"
            case .cdi:  return "CDI · Chemical Distribution"
            case .toe:  return "TOE · Terminal Ops Endorsement"
            case .imdg: return "IMDG · Dangerous Goods"
            }
        }

        /// Whether this cert is held by an individual mariner (crew) vs. the
        /// vessel/company. Drives the default owner-type and which fields
        /// matter (an MMC has no IMO; a DOC has no mariner reference).
        var isMarinerCredential: Bool {
            switch self {
            case .mmc, .stcw: return true
            default:          return false
            }
        }

        /// credentialScanner type code for scan-to-autofill, when available.
        var scanType: (code: String, title: String, subtitle: String)? {
            switch self {
            case .mmc:
                return ("uscg_mmc",
                        "Scan your USCG MMC",
                        "Auto-fills mariner reference number, issuing authority and expiration.")
            default:
                return nil
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let r = result { resultBanner(r) }
                if let err = submitError { errorBanner(err) }
                lapseBanner
                scanSection
                formSection
                if !scanWarnings.isEmpty { warningsSection }
                submitButton
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s5)
        }
        .background(palette.bgPrimary.ignoresSafeArea())
        .onAppear { ownerType = ownerEntityType }
        .onChange(of: certType) { _, newValue in
            // Keep owner-type aligned with the credential's natural holder
            // unless the wizard pinned it via the parameter.
            ownerType = newValue.isMarinerCredential ? "crew" : "company"
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "ferry.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Brand.vessel)
                    Text("COMPLIANCE · MARITIME CREDENTIAL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.vessel)
                }
                Spacer(minLength: 0)
                Button {
                    onClose(); dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(palette.bgCardSoft, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text("Attach maritime certificate")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Scan to auto-fill where supported, confirm the details, then attach. We record the issuer and validity window for compliance.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Scan-to-autofill

    @ViewBuilder
    private var scanSection: some View {
        if let scan = certType.scanType {
            CredentialScanCard(
                credentialType: scan.code,
                title: scan.title,
                subtitle: scan.subtitle
            ) { scanned in
                applyScan(scanned)
            }
        } else {
            // No dedicated OCR extractor for this cert type — make the manual
            // path explicit rather than silently hiding the scan affordance.
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("Enter the \(certType.rawValue) details below. Auto-scan isn't available for this credential type yet.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCardSoft.opacity(0.55))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.borderSoft, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Form

    private var formSection: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // Certificate type picker
            fieldGroup(label: "CERTIFICATE TYPE") {
                Menu {
                    ForEach(MaritimeCertType.allCases) { t in
                        Button { certType = t } label: {
                            if t == certType {
                                Label(t.label, systemImage: "checkmark")
                            } else {
                                Text(t.label)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(certType.label)
                            .font(EType.body)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.horizontal, Space.s3)
                    .frame(height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }

            // Owner type — crew member vs. operating company.
            fieldGroup(label: "HELD BY") {
                Picker("Held by", selection: $ownerType) {
                    Text("Crew member").tag("crew")
                    Text("Company").tag("company")
                }
                .pickerStyle(.segmented)
            }

            textField(label: "CERTIFICATE NUMBER",
                      placeholder: "e.g. 1234567",
                      text: $certNumber,
                      flagged: lowConfidenceFields.contains("identifier"))

            textField(label: "ISSUER",
                      placeholder: "e.g. USCG · Flag State · Class Society",
                      text: $issuer,
                      flagged: lowConfidenceFields.contains("issuingAuthority"))

            // Vessel IMO only matters for vessel/company-held certs.
            if !certType.isMarinerCredential {
                textField(label: "VESSEL IMO NUMBER",
                          placeholder: "e.g. 9074729",
                          text: $vesselImoNumber,
                          keyboard: .numberPad,
                          flagged: lowConfidenceFields.contains("imoNumber"))
            }

            textField(label: "ISSUED DATE",
                      placeholder: "YYYY-MM-DD",
                      text: $issuedAt,
                      flagged: lowConfidenceFields.contains("issueDate"))

            textField(label: "EXPIRES",
                      placeholder: "YYYY-MM-DD",
                      text: $expiresAt,
                      flagged: lowConfidenceFields.contains("expirationDate"))
        }
    }

    @ViewBuilder
    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            content()
        }
    }

    private func textField(label: String,
                           placeholder: String,
                           text: Binding<String>,
                           keyboard: UIKeyboardType = .default,
                           flagged: Bool = false) -> some View {
        fieldGroup(label: label) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(placeholder, text: text)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, Space.s3)
                    .frame(height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(flagged ? Brand.warning.opacity(0.7) : palette.borderSoft,
                                          lineWidth: flagged ? 1.4 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                if flagged {
                    Text("Scanned with low confidence — please double-check.")
                        .font(EType.micro)
                        .foregroundStyle(Brand.warning)
                }
            }
        }
    }

    // MARK: Lapse banner

    /// Surfaces when the entered expiry is within 30 days or already past.
    @ViewBuilder
    private var lapseBanner: some View {
        if let days = daysUntilExpiry {
            if days < 0 {
                banner(icon: "exclamationmark.triangle.fill",
                       tint: Brand.danger,
                       title: "Certificate expired",
                       detail: "This credential lapsed \(abs(days)) day\(abs(days) == 1 ? "" : "s") ago. Renew before attaching to stay compliant.")
            } else if days <= 30 {
                banner(icon: "clock.badge.exclamationmark.fill",
                       tint: Brand.warning,
                       title: "Expiring soon",
                       detail: "This credential lapses in \(days) day\(days == 1 ? "" : "s"). Schedule renewal now.")
            }
        }
    }

    /// Days from today to the entered `expiresAt`. nil when unparseable / empty.
    private var daysUntilExpiry: Int? {
        guard !expiresAt.trimmingCharacters(in: .whitespaces).isEmpty,
              let date = Self.dateFormatter.date(from: expiresAt.trimmingCharacters(in: .whitespaces))
        else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: end).day
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: Warnings / result / error

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(scanWarnings, id: \.self) { w in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text(w)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintWarning)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Renders the server status VERBATIM. Only "verified" / "clear" / "active"
    /// read as a confirmed success; every other status (pending,
    /// provider_unavailable, manual_review, null) reads as a neutral warning —
    /// never a fake green.
    @ViewBuilder
    private func resultBanner(_ r: RegistrationAPI.AttachResult) -> some View {
        let raw = (r.status ?? "pending").lowercased()
        let isVerified = raw == "verified" || raw == "clear" || raw == "active"
        let tint = isVerified ? Brand.success : Brand.warning
        let icon = isVerified ? "checkmark.seal.fill" : "hourglass"
        let title = isVerified
            ? "Certificate attached · \(r.status ?? "verified")"
            : "Submitted · \(r.status ?? "pending review")"
        let detail: String = {
            if isVerified {
                return "The credential is on file. We'll monitor the validity window and alert you before it lapses."
            }
            if raw == "provider_unavailable" {
                return "Validation provider is unavailable — your submission is queued for manual review. No verified status is granted yet."
            }
            return "Submitted for review. No verified status is granted until validation completes."
        }()
        VStack(alignment: .leading, spacing: 8) {
            banner(icon: icon, tint: tint, title: title, detail: detail)
            if let warnings = r.warnings, !warnings.isEmpty {
                ForEach(warnings, id: \.self) { w in
                    Text("⚠ " + w)
                        .font(EType.caption)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        banner(icon: "xmark.octagon.fill",
               tint: Brand.danger,
               title: "Couldn't attach certificate",
               detail: message)
    }

    private func banner(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Submit

    private var canSubmit: Bool {
        !certNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var submitButton: some View {
        VStack(spacing: 6) {
            CTAButton(
                title: submitting ? "Attaching…" : "Attach certificate",
                action: { Task { await submit() } },
                trailingIcon: submitting ? nil : "arrow.right",
                isLoading: submitting || !canSubmit
            )
            if !canSubmit {
                Text("Enter the certificate number to continue.")
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    @MainActor
    private func submit() async {
        guard !submitting, canSubmit else { return }
        submitting = true
        submitError = nil
        result = nil
        defer { submitting = false }

        func nilIfBlank(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }

        do {
            let r = try await EusoTripAPI.shared.registration.attachMaritimeCert(
                ownerEntityId: ownerEntityId,
                ownerEntityType: ownerType,
                certType: certType.rawValue,
                certNumber: nilIfBlank(certNumber),
                issuer: nilIfBlank(issuer),
                vesselImoNumber: certType.isMarinerCredential ? nil : nilIfBlank(vesselImoNumber),
                issuedAt: nilIfBlank(issuedAt),
                expiresAt: nilIfBlank(expiresAt)
            )
            result = r
            onAttached?(r)
        } catch let e as LocalizedError {
            submitError = e.errorDescription ?? "Attach failed. Please try again."
        } catch {
            submitError = error.localizedDescription
        }
    }

    // MARK: Scan → form mapping

    /// Folds a scanned credential into the editable fields. Only overwrites
    /// a field when the OCR returned a non-empty value, so a partial scan
    /// never blanks out something the user already typed. Low-confidence
    /// fields are flagged for human review.
    private func applyScan(_ s: CredentialScannerAPI.ScannedCredential) {
        scanWarnings = s.warnings
        var flagged: [String] = []

        func apply(_ field: CredentialScannerAPI.ScannedField?, to binding: inout String, key: String) {
            guard let field, let value = field.value?.stringValue,
                  !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            binding = value
            if field.confidence < 0.85 { flagged.append(key) }
        }

        apply(s.identifier,        to: &certNumber,      key: "identifier")
        apply(s.issuingAuthority,  to: &issuer,          key: "issuingAuthority")
        apply(s.issueDate,         to: &issuedAt,        key: "issueDate")
        apply(s.expirationDate,    to: &expiresAt,       key: "expirationDate")
        if !certType.isMarinerCredential {
            apply(s.imoNumber, to: &vesselImoNumber, key: "imoNumber")
        }

        lowConfidenceFields = flagged
    }
}

// MARK: - Previews

#Preview("1105 · Maritime cert · Night") {
    MaritimeCertSheet(ownerEntityId: 4821, ownerEntityType: "crew")
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPrimary)
}

#Preview("1105 · Maritime cert · Afternoon") {
    MaritimeCertSheet(ownerEntityId: 4821, ownerEntityType: "company")
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPrimary)
}
