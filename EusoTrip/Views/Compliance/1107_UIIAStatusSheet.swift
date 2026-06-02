//
//  1107_UIIAStatusSheet.swift
//  EusoTrip — Compliance · IANA UIIA status (RIOS spec §11).
//
//  Sheet content view (capture/confirm precedent — §1100-1110 are acceptable
//  as .sheet content). Collects the UIIA insurer, an editable list of
//  equipment-provider IDs, and a "valid until" date, then attaches the
//  Intermodal UIIA via `registration.attachIntermodalUIIA`. Renders one
//  ActiveCard per equipment provider with the server-attested status verbatim
//  — never a fabricated "verified" badge.
//

import SwiftUI

struct UIIAStatusSheet: View {
    /// The company the UIIA attaches to. Supplied by the presenting
    /// wizard (1111) — required, because the IANA UIIA is a company-level
    /// equipment-interchange agreement.
    let companyId: Int
    /// Optional dismiss closure injected by the presenter so the sheet
    /// can close itself after a confirmed attach. Falls back to the
    /// environment dismiss when nil (e.g. isolated previews).
    var onClose: (() -> Void)? = nil

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    // MARK: Form state
    @State private var insurer: String = ""
    @State private var newProviderId: String = ""
    @State private var providerIds: [String] = []
    @State private var validUntil: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasValidUntil: Bool = true

    // MARK: Submit state
    @State private var submitting = false
    @State private var result: RegistrationAPI.AttachResult? = nil
    @State private var submitError: String? = nil

    private var isoDateFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }

    /// At least one equipment provider is required to register a UIIA —
    /// the agreement exists between the motor carrier and the equipment
    /// providers (steamship lines / leasing pools) it interchanges with.
    private var canSubmit: Bool {
        !submitting
            && !insurer.trimmingCharacters(in: .whitespaces).isEmpty
            && !providerIds.isEmpty
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let result { resultBanner(result) }
                if let err = submitError { errorBanner(err) }
                insurerCard
                providersCard
                validityCard
                submitButton
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s5)
        }
        .background(palette.bgPrimary.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("COMPLIANCE · INTERMODAL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("IANA UIIA status")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Uniform Intermodal Interchange & Facilities Access Agreement — register your insurer, the equipment providers you interchange with, and the agreement's validity.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s3)
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(palette.bgCardSoft))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: Insurer

    private var insurerCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                sectionLabel("UIIA INSURER", icon: "checkmark.shield")
                GlassField(
                    label: "Insurer (UIIA-approved)",
                    placeholder: "e.g. Avalon Risk Management",
                    icon: "building.columns",
                    text: $insurer,
                    autocapitalization: .words
                )
            }
        }
    }

    // MARK: Equipment providers

    private var providersCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                sectionLabel("EQUIPMENT PROVIDERS", icon: "shippingbox")
                Text("Add each equipment-provider SCAC / EP ID you interchange chassis & containers with under this UIIA.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.s2) {
                    GlassField(
                        label: "Provider ID / SCAC",
                        placeholder: "e.g. MAEU",
                        icon: "number",
                        text: $newProviderId,
                        autocapitalization: .characters
                    )
                    Button(action: addProvider) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(canAddProvider ? AnyShapeStyle(LinearGradient.diagonal)
                                                         : AnyShapeStyle(palette.bgCardSoft))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddProvider)
                    .accessibilityLabel("Add equipment provider")
                    // Pad the button down so it baselines with the field
                    // (the field reserves a label row above its input).
                    .padding(.top, 22)
                }

                if providerIds.isEmpty {
                    Text("No equipment providers added yet.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, Space.s1)
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(providerIds, id: \.self) { pid in
                            providerRow(pid)
                        }
                    }
                }
            }
        }
    }

    private var canAddProvider: Bool {
        let trimmed = newProviderId.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !providerIds.contains(trimmed.uppercased())
    }

    private func addProvider() {
        let trimmed = newProviderId.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty, !providerIds.contains(trimmed) else { return }
        providerIds.append(trimmed)
        newProviderId = ""
    }

    /// One equipment provider rendered as an Activecard-style row. The
    /// status it reflects is the server's attested UIIA status (from
    /// `result.status`) once attached — until then it reads "Not yet
    /// submitted" in neutral, never a fake "active".
    @ViewBuilder
    private func providerRow(_ pid: String) -> some View {
        let state = providerState
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(palette.bgCardSoft)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(state.color)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(pid)
                    .font(EType.mono(.body))
                    .foregroundStyle(palette.textPrimary)
                Text(state.label)
                    .font(EType.caption)
                    .foregroundStyle(state.color)
            }
            Spacer(minLength: 0)

            if result == nil {
                Button {
                    providerIds.removeAll { $0 == pid }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(pid)")
            } else {
                Image(systemName: state.glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(state.color)
            }
        }
        .eusoRow()
    }

    /// Honest status mapping shared by every provider row. We never claim
    /// "active/verified" unless the server returned status == "active" or
    /// "verified". Pending / provider-unavailable / unknown statuses render
    /// in Brand.warning as a neutral "review" state.
    private struct ProviderState {
        let label: String
        let color: Color
        let glyph: String
    }

    private var providerState: ProviderState {
        guard let result else {
            return ProviderState(label: "Not yet submitted",
                                 color: palette.textTertiary,
                                 glyph: "circle")
        }
        switch (result.status ?? "").lowercased() {
        case "active", "verified", "approved", "valid":
            return ProviderState(label: "Active under UIIA",
                                 color: Brand.success,
                                 glyph: "checkmark.seal.fill")
        case "pending", "submitted", "in_review", "review":
            return ProviderState(label: "Pending review",
                                 color: Brand.warning,
                                 glyph: "clock.fill")
        case "provider_unavailable", "unavailable":
            return ProviderState(label: "Provider unavailable — manual review",
                                 color: Brand.warning,
                                 glyph: "exclamationmark.triangle.fill")
        case "expired", "rejected", "blocked":
            return ProviderState(label: (result.status ?? "rejected").capitalized,
                                 color: Brand.danger,
                                 glyph: "xmark.octagon.fill")
        case "":
            return ProviderState(label: "Submitted — status pending",
                                 color: Brand.warning,
                                 glyph: "clock.fill")
        default:
            return ProviderState(label: "\(result.status ?? "Unknown") — manual review",
                                 color: Brand.warning,
                                 glyph: "questionmark.circle.fill")
        }
    }

    // MARK: Validity

    private var validityCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                sectionLabel("AGREEMENT VALIDITY", icon: "calendar")
                Toggle(isOn: $hasValidUntil.animation(.easeOut(duration: 0.15))) {
                    Text("Set a valid-until date")
                        .font(EType.body)
                        .foregroundStyle(palette.textPrimary)
                }
                .tint(Brand.blue)

                if hasValidUntil {
                    DatePicker(
                        "Valid until",
                        selection: $validUntil,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .tint(Brand.blue)
                } else {
                    Text("No expiry recorded — the UIIA will register as open-ended until you set a renewal date.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Submit

    private var submitButton: some View {
        VStack(spacing: Space.s2) {
            CTAButton(
                title: result == nil
                    ? (submitting ? "Submitting…" : "Register UIIA")
                    : "Re-submit UIIA",
                action: { Task { await submit() } },
                trailingIcon: result == nil ? "arrow.right" : "arrow.clockwise",
                isLoading: submitting
            )
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.55)

            if !canSubmit && !submitting {
                Text(requirementHint)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var requirementHint: String {
        if insurer.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Add the UIIA-approved insurer to continue."
        }
        if providerIds.isEmpty {
            return "Add at least one equipment provider to register the UIIA."
        }
        return ""
    }

    private func submit() async {
        guard canSubmit else { return }
        submitting = true
        submitError = nil
        defer { submitting = false }

        let validUntilString: String? = hasValidUntil ? isoDateFormatter.string(from: validUntil) : nil
        let insurerValue = insurer.trimmingCharacters(in: .whitespaces)

        do {
            let r = try await EusoTripAPI.shared.registration.attachIntermodalUIIA(
                companyId: companyId,
                insurer: insurerValue.isEmpty ? nil : insurerValue,
                equipmentProviderIds: providerIds,
                validUntil: validUntilString
            )
            result = r
        } catch let apiErr as EusoTripAPIError {
            submitError = apiErr.errorDescription ?? "Couldn't register the UIIA. Try again."
        } catch let local as LocalizedError {
            submitError = local.errorDescription ?? "Couldn't register the UIIA. Try again."
        } catch {
            submitError = error.localizedDescription
        }
    }

    // MARK: Result + error banners (honest states)

    @ViewBuilder
    private func resultBanner(_ r: AttachResult) -> some View {
        let state = providerState
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: state.glyph)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(state.color)
                    Text(state.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(state.color)
                    Spacer(minLength: 0)
                    StatusPill(text: r.status ?? "submitted",
                               kind: state.color == Brand.success ? .success
                                   : state.color == Brand.danger ? .danger
                                   : .warning)
                }
                if let expires = r.expiresAt, !expires.isEmpty {
                    metaRow(icon: "calendar", text: "Valid until \(displayDate(expires))")
                }
                if let id = r.id {
                    metaRow(icon: "number", text: "UIIA record #\(id)")
                }
                if let warnings = r.warnings, !warnings.isEmpty {
                    ForEach(warnings, id: \.self) { w in
                        metaRow(icon: "exclamationmark.triangle.fill", text: w, tint: Brand.warning)
                    }
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintDanger)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: Small helpers

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    private func metaRow(icon: String, text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? palette.textSecondary)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(tint ?? palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Reformat an ISO date string to a friendly day; falls back to the
    /// raw string if it isn't parseable so we never hide the server value.
    private func displayDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate]
        if let d = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateStyle = .medium
            return out.string(from: d)
        }
        return iso
    }

    // Local alias so the banner signature stays terse.
    private typealias AttachResult = RegistrationAPI.AttachResult
}

#Preview("1107 · UIIA status · Night") {
    UIIAStatusSheet(companyId: 1)
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("1107 · UIIA status · Afternoon") {
    UIIAStatusSheet(companyId: 1)
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
