//
//  1102_OperatingAuthoritySheet.swift
//  EusoTrip — RIOS §11 · Operating-authority capture + live verify.
//
//  A pushed full-screen capture surface (Shell scaffold, NOT a slide-up)
//  that lets a compliance officer attach a mode/country-specific operating
//  authority to a company and subscribe it to the FMCSA out-of-service
//  monitoring feed.
//
//  Flow:
//    1. Pick transport mode (TRUCK / RAIL / VESSEL / BARGE).
//    2. Pick country (US / CA / MX).
//    3. Pick the authority type valid for that mode×country
//       (USDOT / MC / NSC / SICT / STB / CTA / SEMAR / …).
//    4. For a US truck USDOT/MC, the embedded FMCSALookupCard runs a live
//       SAFER lookup and autofills the authority number + legal name.
//    5. Attach → registration.attachOperatingAuthority. We render the
//       server's AttachResult.status VERBATIM. There is no live registry
//       write-through for most authority types, so the honest server reply
//       is usually "pending" — we surface that as a neutral Brand.warning
//       "Pending review" state, never a fake green "Verified".
//    6. On a successful attach we subscribe the company entity to the
//       FMCSA_OOS monitoring signal so any future out-of-service order
//       trips an alert.
//
//  The struct is named `OperatingAuthoritySheet` so it can be presented as
//  `.sheet` content where a host prefers a sheet, while still being a
//  self-contained full-bleed Shell surface when pushed.
//

import SwiftUI

// MARK: - Domain model

/// Transport mode the authority applies to. `apiValue` is the lowercase
/// token the server expects on `attachOperatingAuthority(mode:)`.
private enum AuthorityMode: String, CaseIterable, Identifiable {
    case truck, rail, vessel, barge
    var id: String { rawValue }

    var apiValue: String { rawValue }
    var label: String {
        switch self {
        case .truck:  return "TRUCK"
        case .rail:   return "RAIL"
        case .vessel: return "VESSEL"
        case .barge:  return "BARGE"
        }
    }
    var icon: String {
        switch self {
        case .truck:  return "box.truck.fill"
        case .rail:   return "tram.fill"
        case .vessel: return "ferry.fill"
        case .barge:  return "sailboat.fill"
        }
    }
    var accent: Color {
        switch self {
        case .truck:  return Brand.blue
        case .rail:   return Brand.rail
        case .vessel: return Brand.vessel
        case .barge:  return Brand.info
        }
    }
}

/// Country the authority is issued under. `apiValue` is the ISO-2 token
/// the server expects on `attachOperatingAuthority(country:)`.
private enum AuthorityCountry: String, CaseIterable, Identifiable {
    case us, ca, mx
    var id: String { rawValue }

    var apiValue: String { rawValue.uppercased() }
    var label: String {
        switch self {
        case .us: return "US"
        case .ca: return "CA"
        case .mx: return "MX"
        }
    }
    var flag: String {
        switch self {
        case .us: return "🇺🇸"
        case .ca: return "🇨🇦"
        case .mx: return "🇲🇽"
        }
    }
}

/// A single selectable authority type, scoped to a mode×country.
/// `apiValue` is the canonical token the registry stores it under.
private struct AuthorityType: Identifiable, Hashable {
    let apiValue: String      // "USDOT", "MC", "NSC", "STB", …
    let label: String         // human label
    let detail: String        // issuing body / note
    var id: String { apiValue }
}

private enum AuthorityCatalog {
    /// The valid authority types for a given mode × country. Returns the
    /// subset the server will accept; the picker only ever offers these.
    static func types(mode: AuthorityMode, country: AuthorityCountry) -> [AuthorityType] {
        switch (mode, country) {
        case (.truck, .us):
            return [
                AuthorityType(apiValue: "USDOT", label: "USDOT Number",       detail: "FMCSA · interstate operating authority"),
                AuthorityType(apiValue: "MC",    label: "MC Number",          detail: "FMCSA · motor carrier / broker authority"),
            ]
        case (.truck, .ca):
            return [
                AuthorityType(apiValue: "NSC",   label: "NSC Number",         detail: "National Safety Code · provincial carrier"),
                AuthorityType(apiValue: "CVOR",  label: "CVOR",               detail: "Commercial Vehicle Operator Registration (ON)"),
            ]
        case (.truck, .mx):
            return [
                AuthorityType(apiValue: "SICT",  label: "SICT Permit",        detail: "Sec. de Infraestructura, Comunicaciones y Transportes"),
                AuthorityType(apiValue: "SCT",   label: "SCT Federal Permit", detail: "Federal autotransporte de carga"),
            ]
        case (.rail, .us):
            return [
                AuthorityType(apiValue: "STB",   label: "STB Authority",      detail: "Surface Transportation Board"),
                AuthorityType(apiValue: "AAR",   label: "AAR Reporting Mark", detail: "Assoc. of American Railroads · reporting mark"),
            ]
        case (.rail, .ca):
            return [
                AuthorityType(apiValue: "CTA",   label: "CTA Certificate",    detail: "Canadian Transportation Agency · COFC"),
            ]
        case (.rail, .mx):
            return [
                AuthorityType(apiValue: "ARTF",  label: "ARTF Concession",    detail: "Agencia Reguladora del Transporte Ferroviario"),
            ]
        case (.vessel, .us):
            return [
                AuthorityType(apiValue: "USCG",  label: "USCG COI",           detail: "US Coast Guard · Certificate of Inspection"),
                AuthorityType(apiValue: "FMC",   label: "FMC License",        detail: "Federal Maritime Commission · OTI/NVOCC"),
            ]
        case (.vessel, .ca):
            return [
                AuthorityType(apiValue: "TCMS",  label: "TC Marine Cert",     detail: "Transport Canada · Marine Safety"),
            ]
        case (.vessel, .mx):
            return [
                AuthorityType(apiValue: "SEMAR", label: "SEMAR Permit",       detail: "Secretaría de Marina · maritime authority"),
            ]
        case (.barge, .us):
            return [
                AuthorityType(apiValue: "USCG",  label: "USCG COI",           detail: "US Coast Guard · inland barge inspection"),
                AuthorityType(apiValue: "STB",   label: "STB Authority",      detail: "Surface Transportation Board · water carrier"),
            ]
        case (.barge, .ca):
            return [
                AuthorityType(apiValue: "TCMS",  label: "TC Marine Cert",     detail: "Transport Canada · inland marine"),
            ]
        case (.barge, .mx):
            return [
                AuthorityType(apiValue: "SEMAR", label: "SEMAR Permit",       detail: "Secretaría de Marina · inland waterway"),
            ]
        }
    }

    /// True when the live FMCSA SAFER lookup card should be shown for the
    /// current selection (US truck USDOT/MC only — that's the one feed
    /// we actually query at registry-time).
    static func supportsFMCSALookup(mode: AuthorityMode, country: AuthorityCountry, type: AuthorityType?) -> FMCSALookupCard.Mode? {
        guard mode == .truck, country == .us, let type else { return nil }
        switch type.apiValue {
        case "USDOT": return .dot
        case "MC":    return .mc
        default:      return nil
        }
    }
}

// MARK: - Submit state machine

private enum AttachPhase: Equatable {
    case idle
    case submitting
    /// Server replied. We hold the verbatim status + any warnings so the
    /// result block can render the HONEST state. `monitoringActive`
    /// reflects whether the FMCSA_OOS subscription came back active.
    case done(status: String, attachId: Int?, expiresAt: String?, warnings: [String], monitoringNote: String?)
    case failed(String)
}

// MARK: - Screen (pushed full-screen Shell wrapper)

struct OperatingAuthoritySheet: View {
    let theme: Theme.Palette
    /// When presented as a pushed full screen, the host can pass a
    /// dismiss handler (back button). When presented as a `.sheet`, the
    /// content uses the environment dismiss instead.
    var onClose: (() -> Void)? = nil

    var body: some View {
        Shell(theme: theme) {
            OperatingAuthorityBody(onClose: onClose)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Audits", systemImage: "doc.text.magnifyingglass", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct OperatingAuthorityBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession

    var onClose: (() -> Void)?

    // Selection state
    @State private var mode: AuthorityMode = .truck
    @State private var country: AuthorityCountry = .us
    @State private var selectedType: AuthorityType?
    @State private var authorityNumber: String = ""

    // FMCSA lookup binding state (drives the embedded card)
    @State private var dotNumber: String = ""
    @State private var mcNumber: String = ""
    @State private var fmcsaLegalName: String?

    // Submit state
    @State private var phase: AttachPhase = .idle

    private var companyId: Int? {
        guard let raw = session.user?.companyId, let id = Int(raw) else { return nil }
        return id
    }

    private var availableTypes: [AuthorityType] {
        AuthorityCatalog.types(mode: mode, country: country)
    }

    private var fmcsaMode: FMCSALookupCard.Mode? {
        AuthorityCatalog.supportsFMCSALookup(mode: mode, country: country, type: selectedType)
    }

    private var canSubmit: Bool {
        guard companyId != nil, selectedType != nil else { return false }
        if case .submitting = phase { return false }
        return !authorityNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            missingCompanyBanner
            modeSection
            countrySection
            typeSection
            if let fmcsaMode {
                fmcsaSection(fmcsaMode)
            }
            numberSection
            resultSection
            submitButton
            Color.clear.frame(height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.top, 56)
        .onChange(of: mode) { _, _ in resetForSelectionChange() }
        .onChange(of: country) { _, _ in resetForSelectionChange() }
        .onAppear { ensureTypeSelected() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let onClose { onClose() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(palette.bgCardSoft)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("COMPLIANCE · OPERATING AUTHORITY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Attach operating authority")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Capture the credential, run a live registry check where one exists, and enroll the company in out-of-service monitoring.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var missingCompanyBanner: some View {
        if companyId == nil {
            calloutCard(
                icon: "exclamationmark.triangle.fill",
                tint: Brand.warning,
                title: "No company on this session",
                body: "We can't attach an authority without a company context. Sign in as a compliance officer with a company assigned, then retry."
            )
        }
    }

    // MARK: Mode picker

    private var modeSection: some View {
        sectionCard(label: "TRANSPORT MODE", icon: "arrow.triangle.swap") {
            HStack(spacing: 8) {
                ForEach(AuthorityMode.allCases) { m in
                    chip(
                        title: m.label,
                        icon: m.icon,
                        accent: m.accent,
                        selected: mode == m
                    ) { mode = m }
                }
            }
        }
    }

    // MARK: Country picker

    private var countrySection: some View {
        sectionCard(label: "ISSUING COUNTRY", icon: "globe.americas.fill") {
            HStack(spacing: 8) {
                ForEach(AuthorityCountry.allCases) { c in
                    chip(
                        title: "\(c.flag)  \(c.label)",
                        icon: nil,
                        accent: Brand.blue,
                        selected: country == c
                    ) { country = c }
                }
            }
        }
    }

    // MARK: Authority type picker

    private var typeSection: some View {
        sectionCard(label: "AUTHORITY TYPE", icon: "doc.badge.gearshape") {
            VStack(spacing: 8) {
                ForEach(availableTypes) { t in
                    typeRow(t)
                }
            }
        }
    }

    private func typeRow(_ t: AuthorityType) -> some View {
        let isSel = selectedType?.apiValue == t.apiValue
        return Button {
            selectedType = t
            // Reset the number when switching type so a USDOT value doesn't
            // bleed into an MC field, and clear the FMCSA autofill.
            authorityNumber = ""
            fmcsaLegalName = nil
            if case .done = phase { phase = .idle }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSel ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSel ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(t.detail)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(t.apiValue)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSel ? palette.bgCardSoft : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSel ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.5)) : AnyShapeStyle(palette.borderFaint),
                                  lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: FMCSA live lookup (US truck only)

    private func fmcsaSection(_ lookupMode: FMCSALookupCard.Mode) -> some View {
        sectionCard(label: "LIVE FMCSA VERIFY", icon: "checkmark.shield") {
            VStack(alignment: .leading, spacing: Space.s2) {
                FMCSALookupCard(
                    mode: lookupMode,
                    dotNumber: $dotNumber,
                    mcNumber: $mcNumber,
                    compact: true
                ) { lookup in
                    applyFMCSA(lookup, lookupMode: lookupMode)
                }
                if let name = fmcsaLegalName {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Brand.success)
                        Text("Autofilled from SAFER: \(name)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func applyFMCSA(_ lookup: FMCSACarrierLookup, lookupMode: FMCSALookupCard.Mode) {
        // Pull the authority number straight from the verified envelope and
        // drop it into the submit field so the attach call carries the
        // registry-confirmed value.
        if lookupMode == .dot, let dot = lookup.authority?.dotNumber, !dot.isEmpty {
            authorityNumber = dot
        } else {
            let entered = (lookupMode == .dot ? dotNumber : mcNumber)
                .trimmingCharacters(in: .whitespaces)
            if !entered.isEmpty { authorityNumber = entered }
        }
        fmcsaLegalName = lookup.companyProfile?.legalName
        if case .done = phase { phase = .idle }
    }

    // MARK: Authority number entry

    private var numberSection: some View {
        sectionCard(label: numberFieldLabel, icon: "number") {
            VStack(alignment: .leading, spacing: 6) {
                TextField(numberPlaceholder, text: $authorityNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .background(palette.bgCardSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: authorityNumber) { _, _ in
                        if case .done = phase { phase = .idle }
                    }
                if fmcsaMode != nil {
                    Text("USDOT/MC numbers are filled automatically once SAFER verify succeeds — you can override above.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var numberFieldLabel: String {
        if let t = selectedType { return "\(t.apiValue) NUMBER" }
        return "AUTHORITY NUMBER"
    }
    private var numberPlaceholder: String {
        switch selectedType?.apiValue {
        case "USDOT": return "e.g. 1234567"
        case "MC":    return "e.g. 123456"
        case "NSC":   return "e.g. NSC-000000"
        case "SICT", "SCT": return "Permiso federal"
        case "STB":   return "e.g. STB-FD-00000"
        case .some(let v): return v
        case .none:   return "Authority / permit number"
        }
    }

    // MARK: Result (HONEST status rendering)

    @ViewBuilder
    private var resultSection: some View {
        switch phase {
        case .idle, .submitting:
            EmptyView()
        case .failed(let message):
            calloutCard(
                icon: "xmark.octagon.fill",
                tint: Brand.danger,
                title: "Attach failed",
                body: message
            )
        case .done(let status, let attachId, let expiresAt, let warnings, let monitoringNote):
            doneCard(status: status, attachId: attachId, expiresAt: expiresAt,
                     warnings: warnings, monitoringNote: monitoringNote)
        }
    }

    private func doneCard(status: String, attachId: Int?, expiresAt: String?, warnings: [String], monitoringNote: String?) -> some View {
        let look = StatusLook(status: status)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: look.icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(look.tint)
                VStack(alignment: .leading, spacing: 1) {
                    // Verbatim server status, prettified for caps only.
                    Text(look.headline)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(look.tint)
                    Text("Server status: \(status)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            Text(look.body)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let attachId {
                metaRow(label: "Record ID", value: "#\(attachId)")
            }
            if let expiresAt, !expiresAt.isEmpty {
                metaRow(label: "Expires", value: expiresAt)
            }
            if let monitoringNote {
                metaRow(label: "FMCSA OOS monitor", value: monitoringNote)
            }
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { w in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Brand.warning)
                            Text(w)
                                .font(EType.caption)
                                .foregroundStyle(Brand.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(look.tint.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Submit

    private var submitButton: some View {
        VStack(spacing: 8) {
            CTAButton(
                title: submitTitle,
                action: { Task { await submit() } },
                trailingIcon: "checkmark.shield",
                isLoading: { if case .submitting = phase { return true } else { return false } }()
            )
            .opacity(canSubmit ? 1.0 : 0.5)
            .allowsHitTesting(canSubmit)
            Text("Most registries have no real-time write-back, so the attach lands as “pending review” until the issuing body confirms. We never report a credential as verified on the issuer's behalf.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private var submitTitle: String {
        if case .submitting = phase { return "Attaching…" }
        if case .done = phase { return "Attach another" }
        return "Attach authority"
    }

    @MainActor
    private func submit() async {
        guard let companyId, let type = selectedType else { return }

        // "Attach another" — reset rather than re-submit the same record.
        if case .done = phase {
            phase = .idle
            authorityNumber = ""
            fmcsaLegalName = nil
            dotNumber = ""
            mcNumber = ""
            return
        }

        let number = authorityNumber.trimmingCharacters(in: .whitespaces)
        guard !number.isEmpty else { return }

        phase = .submitting
        do {
            let result = try await EusoTripAPI.shared.registration.attachOperatingAuthority(
                companyId: companyId,
                mode: mode.apiValue,
                country: country.apiValue,
                authorityType: type.apiValue,
                authorityNumber: number
            )

            // Enroll the company in FMCSA out-of-service monitoring. Surface
            // the subscription's HONEST active/next-check state — if the
            // feed isn't live the server returns active=false / nil, which
            // we report verbatim rather than implying a watch is running.
            var monitoringNote: String? = nil
            do {
                let sub = try await EusoTripAPI.shared.monitoring.subscribeEntity(
                    entityId: companyId,
                    entityType: "company",
                    signal: "FMCSA_OOS",
                    intervalDays: 1
                )
                if sub.active == true {
                    if let due = sub.nextCheckDue, !due.isEmpty {
                        monitoringNote = "Active · next check \(due)"
                    } else {
                        monitoringNote = "Active"
                    }
                } else {
                    monitoringNote = "Subscribed — pending first check"
                }
            } catch {
                monitoringNote = "Couldn't enroll OOS monitor: " + errorText(error)
            }

            phase = .done(
                status: result.status ?? "pending",
                attachId: result.id,
                expiresAt: result.expiresAt,
                warnings: result.warnings ?? [],
                monitoringNote: monitoringNote
            )
        } catch {
            phase = .failed(errorText(error))
        }
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? (error as NSError).localizedDescription
    }

    // MARK: Selection housekeeping

    private func ensureTypeSelected() {
        if selectedType == nil || !availableTypes.contains(where: { $0.apiValue == selectedType?.apiValue }) {
            selectedType = availableTypes.first
        }
    }

    private func resetForSelectionChange() {
        ensureTypeSelected()
        authorityNumber = ""
        fmcsaLegalName = nil
        dotNumber = ""
        mcNumber = ""
        if case .done = phase { phase = .idle }
        if case .failed = phase { phase = .idle }
    }

    // MARK: Reusable bits

    private func sectionCard<Content: View>(
        label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textSecondary)
            }
            content()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard()
    }

    @ViewBuilder
    private func chip(title: String, icon: String?, accent: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .heavy))
                }
                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Color.white : palette.textPrimary)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if selected {
                        accent
                    } else {
                        palette.bgCardSoft
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? accent : palette.borderSoft, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func calloutCard(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(body)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Status → honest visual mapping

/// Maps a verbatim server status string to a neutral/positive/negative
/// visual. The ONLY statuses that earn a green "Verified" are explicit
/// "verified"/"active"/"approved" replies — everything else (pending,
/// provider_unavailable, unknown, null) reads as a neutral Brand.warning
/// "Pending review", never a fabricated success.
private struct StatusLook {
    let tint: Color
    let icon: String
    let headline: String
    let body: String

    init(status raw: String) {
        let s = raw.lowercased()
        switch s {
        case "verified", "active", "approved", "clear", "valid":
            tint = Brand.success
            icon = "checkmark.seal.fill"
            headline = "AUTHORITY VERIFIED"
            body = "The issuing registry confirmed this authority. It's attached and active on the company record."
        case "rejected", "denied", "revoked", "blocked", "invalid", "failed":
            tint = Brand.danger
            icon = "xmark.octagon.fill"
            headline = "NOT ACCEPTED"
            body = "The registry did not accept this authority. Review the warnings below and correct the credential."
        case "provider_unavailable", "unavailable":
            tint = Brand.warning
            icon = "wifi.exclamationmark"
            headline = "PROVIDER UNAVAILABLE"
            body = "The verifying registry couldn't be reached. The authority is recorded and queued for manual review — it is not marked verified."
        default:
            // pending, queued, submitted, manual_review, unknown, null → neutral
            tint = Brand.warning
            icon = "clock.badge.checkmark"
            headline = "PENDING REVIEW"
            body = "Recorded on the company. Most registries have no real-time feed, so this stays pending until the issuing body confirms — we don't fake a verified state."
        }
    }
}

// MARK: - Previews

#Preview("1102 · Operating Authority · Night") {
    OperatingAuthoritySheet(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("1102 · Operating Authority · Afternoon") {
    OperatingAuthoritySheet(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
