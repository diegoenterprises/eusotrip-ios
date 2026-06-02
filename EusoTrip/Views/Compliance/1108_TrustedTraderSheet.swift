//
//  1108_TrustedTraderSheet.swift
//  EusoTrip — Compliance · Trusted-trader program attach (RIOS §11, §1108).
//
//  A capture/confirm SHEET (the 1100–1110 capture precedent — acceptable as
//  .sheet content per the push-nav mandate). Lets a compliance officer attach
//  a customs trusted-trader program credential (CTPAT / PIP / OEA / FAST) to a
//  company so cross-border lanes can read the cleared status.
//
//  Calls registration.attachTrustedTrader. Renders the server status VERBATIM:
//  green only when the returned status is "verified"/"active"; otherwise a
//  neutral "Pending review" / "Provider unavailable" state — never a fake
//  success. Thrown errors are surfaced via LocalizedError.
//

import SwiftUI

struct TrustedTraderSheet: View {
    /// Company the credential attaches to. Defaulted from the session by the
    /// caller when known; editable here so an officer can target another
    /// company in their portfolio.
    var companyId: Int? = nil
    /// Optional dismissal hook — the sheet host (a .sheet presenter) injects
    /// this so the "Done" affordance can close the sheet after a successful
    /// attach. Defaults to a no-op so #Preview / isolated use still compiles.
    var onClose: () -> Void = {}

    @EnvironmentObject private var session: EusoTripSession
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // MARK: Form state
    @State private var companyIdText: String = ""
    @State private var program: Program = .ctpat
    @State private var validUntil: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasValidUntil: Bool = true
    @State private var lastAudit: Date = Date()
    @State private var hasLastAudit: Bool = false

    // MARK: Submit state
    @State private var submitting = false
    @State private var result: RegistrationAPI.AttachResult? = nil
    @State private var errorText: String? = nil

    // MARK: Trusted-trader programs (customs MRA portfolio)
    private enum Program: String, CaseIterable, Identifiable {
        case ctpat = "CTPAT"
        case pip   = "PIP"
        case oea   = "OEA"
        case fast  = "FAST"
        var id: String { rawValue }
        /// Lower-cased slug sent to the server.
        var slug: String { rawValue.lowercased() }
        var fullName: String {
            switch self {
            case .ctpat: return "Customs-Trade Partnership Against Terrorism"
            case .pip:   return "Partners in Protection (Canada)"
            case .oea:   return "Operador Económico Autorizado (Mexico)"
            case .fast:  return "Free and Secure Trade"
            }
        }
        var jurisdiction: String {
            switch self {
            case .ctpat: return "US · CBP"
            case .pip:   return "CA · CBSA"
            case .oea:   return "MX · SAT"
            case .fast:  return "US/CA/MX"
            }
        }
        var glyph: String {
            switch self {
            case .ctpat: return "shield.lefthalf.filled"
            case .pip:   return "leaf.fill"
            case .oea:   return "building.columns.fill"
            case .fast:  return "bolt.shield.fill"
            }
        }
    }

    private var resolvedCompanyId: Int? {
        if let n = Int(companyIdText.trimmingCharacters(in: .whitespaces)), n > 0 { return n }
        return nil
    }

    private var canSubmit: Bool {
        resolvedCompanyId != nil && !submitting
    }

    private var theme: Theme.Palette {
        colorScheme == .dark ? Theme.dark : Theme.light
    }

    var body: some View {
        Shell(theme: theme) { content } nav: { EmptyView() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            companyField
            programPicker
            datesCard
            if let result { resultCard(result) }
            else if let errorText { errorCard(errorText) }
            ctaRow
            Color.clear.frame(height: Space.s6)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s6)
        .onAppear(perform: seedCompanyId)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE · TRUSTED TRADER")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Attach trusted-trader status")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Text("Record a customs trusted-trader program so cross-border lanes read the company's cleared standing. Status reflects the server record — it is not self-certified.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Company

    private var companyField: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                GlassField(
                    label: "Company ID",
                    placeholder: "e.g. 1",
                    icon: "number",
                    text: $companyIdText,
                    keyboardType: .numberPad,
                    error: (companyIdText.isEmpty || resolvedCompanyId != nil)
                        ? nil
                        : "Enter a valid numeric company ID"
                )
                Text("The company this credential is being attached to.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Program picker

    private var programPicker: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("PROGRAM")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                ForEach(Program.allCases) { p in
                    programRow(p)
                }
            }
        }
    }

    private func programRow(_ p: Program) -> some View {
        let selected = program == p
        return Button {
            withAnimation(.easeOut(duration: 0.12)) { program = p }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(selected ? AnyShapeStyle(LinearGradient.diagonal)
                                       : AnyShapeStyle(palette.bgCardSoft))
                        .frame(width: 38, height: 38)
                    Image(systemName: p.glyph)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.rawValue)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text(p.jurisdiction)
                            .font(EType.micro).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text(p.fullName)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(selected ? Brand.blue : palette.borderStrong)
            }
            .padding(.vertical, Space.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Dates

    private var datesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                dateRow(
                    title: "Valid until",
                    subtitle: "Program certification expiry.",
                    isOn: $hasValidUntil,
                    date: $validUntil,
                    range: Date()...
                )
                Divider().overlay(palette.borderFaint)
                dateRow(
                    title: "Last audit",
                    subtitle: "Most recent CBP/CBSA/SAT validation.",
                    isOn: $hasLastAudit,
                    date: $lastAudit,
                    range: ...Date()
                )
            }
        }
    }

    @ViewBuilder
    private func dateRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        date: Binding<Date>,
        range: PartialRangeFrom<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(EType.caption).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: isOn).labelsHidden().tint(Brand.blue)
            }
            if isOn.wrappedValue {
                DatePicker("", selection: date, in: range, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Brand.blue)
            }
        }
    }

    @ViewBuilder
    private func dateRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        date: Binding<Date>,
        range: PartialRangeThrough<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(EType.caption).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: isOn).labelsHidden().tint(Brand.blue)
            }
            if isOn.wrappedValue {
                DatePicker("", selection: date, in: range, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Brand.blue)
            }
        }
    }

    // MARK: Result / error

    /// HONEST STATE: read the server status verbatim. Green only for the
    /// affirmatively-cleared states; everything else is a neutral / warning
    /// pending state, never a fabricated success.
    private func resultCard(_ r: RegistrationAPI.AttachResult) -> some View {
        let status = (r.status ?? "pending").lowercased()
        let cleared = status == "verified" || status == "active" || status == "approved"
        let pending = status == "pending" || status == "submitted" || status == "under_review"
        let kind: StatusPill.Kind = cleared ? .success : (pending ? .warning : .neutral)
        let accent: Color = cleared ? Brand.success : (pending ? Brand.warning : palette.textSecondary)

        return GlassCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Image(systemName: cleared ? "checkmark.seal.fill"
                                              : (pending ? "clock.fill" : "exclamationmark.triangle.fill"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline(for: status, cleared: cleared, pending: pending))
                            .font(EType.title)
                            .foregroundStyle(palette.textPrimary)
                        Text("\(program.rawValue) · \(program.jurisdiction)")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    StatusPill(text: r.status ?? "pending", kind: kind)
                }

                // Verbatim server detail rows.
                VStack(alignment: .leading, spacing: Space.s2) {
                    if let id = r.id {
                        detailRow("Record ID", "#\(id)")
                    }
                    if let exp = r.expiresAt, !exp.isEmpty {
                        detailRow("Expires", exp)
                    }
                    if let warnings = r.warnings, !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("WARNINGS").font(EType.micro).tracking(0.6)
                                .foregroundStyle(Brand.warning)
                            ForEach(warnings, id: \.self) { w in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Brand.warning)
                                    Text(w).font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                if !cleared {
                    Text(pending
                         ? "Submitted. The program record stays in pending review until customs validation completes — it is not yet a cleared credential."
                         : "Provider unavailable or status not confirmed — this credential requires manual review before it counts as cleared.")
                        .font(EType.caption)
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func headline(for status: String, cleared: Bool, pending: Bool) -> String {
        if cleared { return "Trusted-trader status active" }
        if pending { return "Pending review" }
        if status == "provider_unavailable" { return "Provider unavailable" }
        return "Manual review required"
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func errorCard(_ text: String) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Brand.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn't attach credential")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(text).font(EType.caption).foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: CTA

    private var ctaRow: some View {
        VStack(spacing: Space.s2) {
            CTAButton(
                title: result != nil ? "Re-submit" : "Attach \(program.rawValue)",
                action: { Task { await submit() } },
                trailingIcon: "checkmark.seal",
                isLoading: submitting
            )
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1.0 : 0.55)

            if result != nil {
                Button { onClose(); dismiss() } label: {
                    Text("Done")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Actions

    private func seedCompanyId() {
        guard companyIdText.isEmpty else { return }
        if let cid = companyId, cid > 0 {
            companyIdText = String(cid)
        } else if let s = session.user?.companyId, let n = Int(s), n > 0 {
            // The session stores companyId as a String; only seed when it
            // resolves to a real numeric id (never seed a slug like
            // "demo-fleet-1" into a numeric field).
            companyIdText = String(n)
        }
    }

    private func submit() async {
        guard let cid = resolvedCompanyId else { return }
        submitting = true
        errorText = nil
        result = nil

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let validUntilStr = hasValidUntil ? iso.string(from: validUntil) : nil
        let lastAuditStr  = hasLastAudit ? iso.string(from: lastAudit) : nil

        do {
            let r = try await EusoTripAPI.shared.registration.attachTrustedTrader(
                companyId: cid,
                program: program.slug,
                validUntil: validUntilStr,
                lastAudit: lastAuditStr
            )
            result = r
        } catch let e as LocalizedError {
            errorText = e.errorDescription ?? "Request failed."
        } catch {
            errorText = error.localizedDescription
        }
        submitting = false
    }
}

#Preview("1108 · Trusted Trader · Night") {
    TrustedTraderSheet(companyId: 1)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("1108 · Trusted Trader · Afternoon") {
    TrustedTraderSheet(companyId: 1)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
