//
//  1106_RailCertSheet.swift
//  EusoTrip — RIOS §11 · Rail credential capture sheet.
//
//  Captures an FRA / rail operating certificate for a PERSON entity
//  (engineer / conductor) and attaches it via
//  `registration.attachRailCert(ownerEntityId, ownerEntityType:"person", …)`.
//
//  Presented as `.sheet` content from the §11 onboarding / renewal flow
//  (capture-sheet precedent, 1100-1110) — NOT the pushed wizard (1111).
//  An optional scan path (CredentialScanCard) pre-fills the cert number
//  and dates from a photo of the physical certificate; every field stays
//  editable so the operator confirms before submit.
//
//  HONEST STATES: the server's `AttachResult.status` is rendered verbatim.
//  "active"/"verified" → green; "pending"/"provider_unavailable"/null →
//  a neutral Brand.warning "Pending review" state, never a fake success.
//  Any thrown error surfaces its LocalizedError description inline.
//

import SwiftUI

// MARK: - Rail cert type catalog (RIOS §11 rail credentials)

/// The rail / FRA credential types accepted by `registration.attachRailCert`.
/// The `code` is the wire value sent as `certType`; the label/blurb drive
/// the picker UI. 49 CFR §240/§242 govern engineer & conductor certs and
/// mandate recertification at least every 36 months.
private enum RailCertType: String, CaseIterable, Identifiable {
    case fraEng240  = "FRA_ENG_240"
    case fraCond242 = "FRA_COND_242"
    case leqp       = "LEQP"
    case lffd       = "LFFD"
    case ptcQual    = "PTC_QUAL"
    case tdg        = "TDG"
    case cror       = "CROR"

    var id: String { rawValue }

    /// Short menu label.
    var label: String {
        switch self {
        case .fraEng240:  return "FRA Engineer (§240)"
        case .fraCond242: return "FRA Conductor (§242)"
        case .leqp:       return "Locomotive Engineer Qual. Program (LEQP)"
        case .lffd:       return "Locomotive Familiarization (LFFD)"
        case .ptcQual:    return "PTC Qualification"
        case .tdg:        return "TDG (Canada — Dangerous Goods)"
        case .cror:       return "CROR (Canadian Rail Operating Rules)"
        }
    }

    /// One-line description shown under the picker.
    var blurb: String {
        switch self {
        case .fraEng240:  return "49 CFR Part 240 — locomotive engineer certification."
        case .fraCond242: return "49 CFR Part 242 — conductor certification."
        case .leqp:       return "Railroad locomotive engineer qualification program."
        case .lffd:       return "Locomotive familiarization for the territory operated."
        case .ptcQual:    return "Positive Train Control operating qualification."
        case .tdg:        return "Transport Canada dangerous-goods handling certificate."
        case .cror:       return "Canadian Rail Operating Rules certification."
        }
    }

    /// SF Symbol for the row.
    var icon: String {
        switch self {
        case .fraEng240, .leqp, .lffd: return "gauge.with.dots.needle.67percent"
        case .fraCond242:              return "person.text.rectangle"
        case .ptcQual:                 return "dot.radiowaves.left.and.right"
        case .tdg:                     return "exclamationmark.triangle"
        case .cror:                    return "doc.text.magnifyingglass"
        }
    }
}

// MARK: - RailCertSheet

struct RailCertSheet: View {

    /// The PERSON entity (engineer / conductor) the cert is being attached to.
    let ownerEntityId: Int

    /// Fired after a successful attach so the host can refresh its gate list.
    /// Carries the server-returned status verbatim.
    var onAttached: (RegistrationAPI.AttachResult) -> Void = { _ in }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var certType: RailCertType = .fraEng240
    @State private var certNumber: String = ""
    @State private var issuedAt: Date = .now
    @State private var hasIssuedAt: Bool = false
    @State private var expiresAt: Date = Calendar.current.date(byAdding: .month, value: 36, to: .now) ?? .now
    @State private var hasExpiresAt: Bool = false

    // Scan path
    @State private var showScan: Bool = false
    @State private var scanWarnings: [String] = []

    // Submit lifecycle
    @State private var submitting: Bool = false
    @State private var submitError: String? = nil
    @State private var result: RegistrationAPI.AttachResult? = nil

    private var canSubmit: Bool {
        !submitting && !certNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header

                    if let result {
                        resultBanner(result)
                    }
                    if let submitError {
                        errorBanner(submitError)
                    }

                    typePicker
                    scanRow
                    fieldsCard
                    recertNote
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s8)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { submitBar }
            .navigationTitle("Rail certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .sheet(isPresented: $showScan) {
                NavigationStack {
                    ScrollView {
                        CredentialScanCard(
                            credentialType: "fra_cert",
                            title: "Scan rail certificate",
                            subtitle: "Photograph the FRA / rail cert — we'll read the number and dates.",
                            onResult: { applyScan($0) }
                        )
                        .padding(Space.s4)
                    }
                    .background(palette.bgPrimary.ignoresSafeArea())
                    .navigationTitle("Scan")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showScan = false }
                        }
                    }
                }
                .presentationDetents([.large])
            }
            .environment(\.palette, palette)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("RIOS §11 · RAIL CREDENTIAL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Attach rail certificate")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Text("Capture an FRA / rail operating credential for this operator. Status is set by the verifier — we never mark a cert verified ourselves.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Cert-type picker

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            fieldLabel("Certificate type", icon: certType.icon)
            Menu {
                ForEach(RailCertType.allCases) { t in
                    Button {
                        certType = t
                    } label: {
                        Label(t.label, systemImage: t.icon)
                    }
                }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: certType.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.rail)
                    Text(certType.label)
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: .infinity)
                .eusoCard(radius: Radius.md)
            }
            .buttonStyle(.plain)

            Text(certType.blurb)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Scan row

    private var scanRow: some View {
        Button { showScan = true } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan the physical certificate")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("Auto-fill the number and dates from a photo")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity)
            .eusoCard(radius: Radius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: Fields card

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            // Cert number
            VStack(alignment: .leading, spacing: Space.s2) {
                fieldLabel("Certificate number", icon: "number")
                TextField("e.g. FRA-240-…", text: $certNumber)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
            }

            // Issued at
            dateRow(
                title: "Issue date",
                icon: "calendar",
                has: $hasIssuedAt,
                date: $issuedAt,
                range: ...Date.now
            )

            IridescentHairline().opacity(0.4)

            // Expires at
            dateRow(
                title: "Expiration date",
                icon: "calendar.badge.exclamationmark",
                has: $hasExpiresAt,
                date: $expiresAt,
                range: Date.now...
            )

            if !scanWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(scanWarnings.enumerated()), id: \.offset) { _, w in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Brand.warning)
                            Text(w)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity)
        .eusoCard(radius: Radius.lg)
    }

    @ViewBuilder
    private func dateRow(title: String,
                         icon: String,
                         has: Binding<Bool>,
                         date: Binding<Date>,
                         range: PartialRangeThrough<Date>) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Toggle(isOn: has) {
                fieldLabel(title, icon: icon)
            }
            .tint(Brand.rail)
            if has.wrappedValue {
                DatePicker("", selection: date, in: range, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Brand.blue)
            }
        }
    }

    @ViewBuilder
    private func dateRow(title: String,
                         icon: String,
                         has: Binding<Bool>,
                         date: Binding<Date>,
                         range: PartialRangeFrom<Date>) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Toggle(isOn: has) {
                fieldLabel(title, icon: icon)
            }
            .tint(Brand.rail)
            if has.wrappedValue {
                DatePicker("", selection: date, in: range, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Brand.blue)
            }
        }
    }

    // MARK: Recert note

    private var recertNote: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("36-month recertification")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("FRA §240/§242 require engineers and conductors to recertify at least every 36 months. Set an expiration so we can remind the operator before it lapses.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintWarning)
        )
    }

    // MARK: Submit bar

    private var submitBar: some View {
        VStack(spacing: 0) {
            IridescentHairline()
            CTAButton(
                title: submitting ? "Attaching…" : "Attach certificate",
                action: { Task { await submit() } },
                trailingIcon: submitting ? nil : "arrow.up.doc",
                isLoading: submitting
            )
            .opacity(canSubmit || submitting ? 1.0 : 0.5)
            .disabled(!canSubmit)
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s2)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: Result + error banners (HONEST STATES)

    @ViewBuilder
    private func resultBanner(_ r: RegistrationAPI.AttachResult) -> some View {
        let raw = (r.status ?? "").lowercased()
        let isVerified = raw == "verified" || raw == "active" || raw == "clear"
        let tone: Color = isVerified ? Brand.success : Brand.warning
        let icon = isVerified ? "checkmark.seal.fill" : "clock.fill"
        let headline = isVerified
            ? "Certificate attached"
            : (raw.isEmpty ? "Submitted — pending review" : "Pending review")

        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tone)
                Text(headline)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                // Server status rendered verbatim.
                StatusPill(text: r.status ?? "pending",
                           kind: isVerified ? .success : .warning)
            }
            if !isVerified {
                Text("The verifier hasn't confirmed this credential yet. It will show as verified only when the verifier clears it — not before.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let exp = r.expiresAt, !exp.isEmpty {
                Text("Expires \(exp)")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            if let warnings = r.warnings, !warnings.isEmpty {
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Brand.warning)
                        Text(w)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tone.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tone.opacity(0.45), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't attach the certificate")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintDanger)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: Helpers

    @ViewBuilder
    private func fieldLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textTertiary)
            Text(text.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    /// Apply a credential-scan result to the form. We only ever pre-fill
    /// editable fields — the operator confirms before submit. Scan warnings
    /// are surfaced so a low-confidence read is never silently trusted.
    private func applyScan(_ scan: CredentialScannerAPI.ScannedCredential) {
        if let num = scan.identifier?.value?.stringValue,
           !num.trimmingCharacters(in: .whitespaces).isEmpty {
            certNumber = num
        }
        if let issued = scan.issueDate?.value?.stringValue,
           let d = Self.parseDate(issued) {
            issuedAt = d
            hasIssuedAt = true
        }
        if let exp = scan.expirationDate?.value?.stringValue,
           let d = Self.parseDate(exp) {
            expiresAt = d
            hasExpiresAt = true
        }
        scanWarnings = scan.warnings
        showScan = false
    }

    /// Parse the common date formats a scan returns. Returns nil so a
    /// malformed read leaves the field at its default instead of guessing.
    private static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let fmts = ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy", "MM-dd-yyyy"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    private static let wireFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        submitError = nil
        result = nil
        let trimmedNumber = certNumber.trimmingCharacters(in: .whitespaces)
        let issuedString = hasIssuedAt ? Self.wireFormatter.string(from: issuedAt) : nil
        let expiresString = hasExpiresAt ? Self.wireFormatter.string(from: expiresAt) : nil
        do {
            let r = try await EusoTripAPI.shared.registration.attachRailCert(
                ownerEntityId: ownerEntityId,
                ownerEntityType: "person",
                certType: certType.rawValue,
                certNumber: trimmedNumber.isEmpty ? nil : trimmedNumber,
                issuedAt: issuedString,
                expiresAt: expiresString
            )
            result = r
            onAttached(r)
        } catch let apiErr as EusoTripAPIError {
            submitError = apiErr.errorDescription ?? "The request failed. Try again."
        } catch let local as LocalizedError {
            submitError = local.errorDescription ?? "The request failed. Try again."
        } catch {
            submitError = error.localizedDescription
        }
        submitting = false
    }
}

#Preview("1106 · Rail cert · Night") {
    RailCertSheet(ownerEntityId: 4021)
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("1106 · Rail cert · Afternoon") {
    RailCertSheet(ownerEntityId: 4021)
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
