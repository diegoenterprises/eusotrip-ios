//
//  1111_OnboardingWizard.swift
//  EusoTrip — Compliance · RIOS §18 "first 60 seconds" onboarding wizard.
//
//  A PUSHED full-screen, per-role / per-country / per-mode onboarding flow
//  (Shell scaffold — NOT a slide-up sheet, per the push-nav mandate). It
//  walks the operator through the RIOS tier ladder:
//
//    Step 0  Profile        — confirm role · country · mode (never retype;
//                             seeded from the signed-in session).
//    Step 1  Tier 1 (KYB)   — companyName + taxId + country →
//                             registration.startTier1; renders the returned
//                             gates verbatim.
//    Step 2  Credentials    — role/mode-branched capture CTAs that PRESENT
//                             the canonical 1100-1109 sheets:
//                               · Carrier (truck) → operating authority,
//                                 insurance COI, clearinghouse consent
//                               · Vessel          → maritime cert
//                               · Rail            → rail cert + UIIA
//                               · Cross-border    → trusted-trader program
//                             plus IDV/liveness + tax-id for any role.
//    Step 3  Tier 2         — collect 1+ UBO + 1+ signer →
//                             registration.startTier2.
//    Step 4  Tier 3         — optional cross-border / hazmat escalation →
//                             registration.requestTier3.
//
//  Honest states throughout: server status strings are rendered verbatim;
//  green/"Verified" only when the server says verified/clear/pass. Pending,
//  provider_unavailable, and null verdicts render as a neutral amber
//  "Pending review" — never a fabricated success. Thrown errors surface
//  via LocalizedError.errorDescription.
//
//  Created by Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wizard root (pushed full screen)

struct OnboardingWizard: View {
    let theme: Theme.Palette

    /// Dismiss handle injected by the pushing controller (back button).
    /// Falls back to the environment dismiss when nil (e.g. previews).
    var onClose: (() -> Void)? = nil

    var body: some View {
        Shell(theme: theme) {
            OnboardingWizardBody(onClose: onClose)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",                    isCurrent: false),
                          NavSlot(label: "Tiers",    systemImage: "square.stack.3d.up.fill",  isCurrent: true)],
                trailing: [NavSlot(label: "Docs",    systemImage: "doc.text.magnifyingglass", isCurrent: false),
                           NavSlot(label: "Me",      systemImage: "person",                   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Mode / country selection model

/// Transport mode the registration is scoped to. Drives which credential
/// captures the wizard surfaces (FMCSA authority vs. maritime cert vs. rail
/// cert + UIIA). `wire` is the value handed to registration.attach* calls.
private enum WizardMode: String, CaseIterable, Identifiable {
    case truck, rail, vessel
    var id: String { rawValue }
    var wire: String { rawValue }
    var label: String {
        switch self {
        case .truck:  return "Truck"
        case .rail:   return "Rail"
        case .vessel: return "Vessel"
        }
    }
    var icon: String {
        switch self {
        case .truck:  return "box.truck.fill"
        case .rail:   return "tram.fill"
        case .vessel: return "ferry.fill"
        }
    }
    var accent: Color {
        switch self {
        case .truck:  return Brand.blue
        case .rail:   return Brand.rail
        case .vessel: return Brand.vessel
        }
    }
}

/// ISO country the registration is filed under. `isCrossBorder` unlocks the
/// trusted-trader (CTPAT / PIP / OEA) credential branch + the Tier 3 path.
private enum WizardCountry: String, CaseIterable, Identifiable {
    case us = "US", ca = "CA", mx = "MX"
    var id: String { rawValue }
    var flag: String {
        switch self { case .us: return "🇺🇸"; case .ca: return "🇨🇦"; case .mx: return "🇲🇽" }
    }
    var name: String {
        switch self { case .us: return "United States"; case .ca: return "Canada"; case .mx: return "Mexico" }
    }
    var taxLabel: String {
        switch self { case .us: return "EIN"; case .ca: return "BN"; case .mx: return "RFC" }
    }
}

// MARK: - Body

private struct OnboardingWizardBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession

    var onClose: (() -> Void)?

    // ---- Navigation
    /// 0 Profile · 1 Tier1 · 2 Credentials · 3 Tier2 · 4 Tier3
    @State private var step: Int = 0

    // ---- Profile (seeded from session — never retype)
    @State private var mode: WizardMode = .truck
    @State private var country: WizardCountry = .us

    // ---- Tier 1 (KYB)
    @State private var companyName: String = ""
    @State private var taxId: String = ""
    @State private var tier1Submitting = false
    @State private var tier1Error: String? = nil
    @State private var progress: RegistrationAPI.TierProgress? = nil

    // ---- Tier 2 (UBO + signers)
    @State private var ubos: [DraftUBO] = [DraftUBO()]
    @State private var signers: [DraftSigner] = [DraftSigner()]
    @State private var tier2Submitting = false
    @State private var tier2Error: String? = nil

    // ---- Tier 3 (escalation)
    @State private var tier3Reason: String = ""
    @State private var tier3Notes: String = ""
    @State private var tier3Submitting = false
    @State private var tier3Error: String? = nil

    // ---- Credential capture sheets (acceptable as .sheet content)
    @State private var activeSheet: CredentialSheet? = nil
    /// Per-credential outcome line keyed by credential id — fed by each
    /// sheet's onComplete / onAttached callback. Rendered honestly.
    @State private var captureOutcomes: [String: CaptureOutcome] = [:]

    // MARK: Resolved session values (seeded, never retyped)

    private var companyId: Int? {
        session.user?.companyId.flatMap { Int($0) }
    }
    private var userId: Int? {
        // AuthUser.id is a String; the API layer wants an Int? userId.
        guard let raw = session.user?.id else { return nil }
        return Int(raw)
    }
    private var role: EusoRole {
        session.user?.roleEnum ?? .catalyst
    }

    /// Step labels for the progress rail at the top.
    private let stepTitles = ["Profile", "Business", "Credentials", "Owners", "Escalation"]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            header
            stepRail
            Group {
                switch step {
                case 0: profileStep
                case 1: tier1Step
                case 2: credentialsStep
                case 3: tier2Step
                default: tier3Step
                }
            }
            tierLadder
            navButtons
            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, 56)
        .onAppear(perform: seedFromSession)
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    if step > 0 { withAnimation { step -= 1 } }
                    else { (onClose ?? { dismiss() })() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(palette.bgCardSoft))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(step > 0 ? "Previous step" : "Close")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("ONBOARDING · \(role.displayName.uppercased())")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text("Get verified")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            Text("Confirm your business, attach the credentials your lane requires, and unlock the tiers that let you transact.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Step rail

    private var stepRail: some View {
        HStack(spacing: 6) {
            ForEach(stepTitles.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? AnyShapeStyle(LinearGradient.diagonal)
                                    : AnyShapeStyle(palette.borderSoft))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Step \(step + 1) of \(stepTitles.count) · \(stepTitles[step])")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .offset(y: 8)
        }
        .padding(.bottom, Space.s4)
    }

    // MARK: Step 0 — Profile

    private var profileStep: some View {
        WizardCard {
            cardTitle("Your lane", icon: "point.topleft.down.to.point.bottomright.curvepath.fill")
            Text("We pre-filled this from your account. Adjust if you're registering for a different lane.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            fieldLabel("Mode")
            HStack(spacing: 8) {
                ForEach(WizardMode.allCases) { m in
                    segChip(title: m.label, icon: m.icon, accent: m.accent, selected: mode == m) {
                        mode = m
                    }
                }
            }

            fieldLabel("Country")
            HStack(spacing: 8) {
                ForEach(WizardCountry.allCases) { c in
                    segChip(title: "\(c.flag) \(c.rawValue)", icon: nil, accent: Brand.blue, selected: country == c) {
                        country = c
                    }
                }
            }

            if isCrossBorder {
                inlineNote(icon: "globe", text: "Cross-border lane — you'll be offered a trusted-trader credential and a Tier 3 escalation.", tint: Brand.info)
            }
        }
    }

    // MARK: Step 1 — Tier 1 (KYB)

    private var tier1Step: some View {
        WizardCard {
            cardTitle("Business identity (Tier 1)", icon: "building.2.fill")
            Text("Your legal name and \(country.taxLabel) start the KYB check. This unlocks test-posting and bidding.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            fieldLabel("Legal company name")
            WizardField(text: $companyName, placeholder: "Acme Logistics LLC")

            fieldLabel("\(country.taxLabel) · tax ID")
            WizardField(text: $taxId, placeholder: country == .us ? "12-3456789" : (country == .ca ? "123456789RT0001" : "ABC123456XYZ"),
                        autocapitalize: country == .us ? .never : .characters)

            if let err = tier1Error { errorLine(err) }

            CTAButton(
                title: tier1Submitting ? "Running KYB…" : "Start Tier 1 →",
                action: { Task { await runTier1() } },
                isLoading: tier1Submitting
            )
            .opacity(canRunTier1 ? 1 : 0.5)
            .allowsHitTesting(canRunTier1 && !tier1Submitting)

            if let p = progress, step == 1 {
                gateList(p.gates ?? [], heading: "KYB gates")
            }
        }
    }

    // MARK: Step 2 — Credentials (role/mode/country branched)

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WizardCard {
                cardTitle("Identity verification", icon: "person.text.rectangle.fill")
                Text("Verify the human behind the account. Required before any tier is granted.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                credentialRow(.idv, title: "ID + liveness check", subtitle: "Scan a government ID, then a selfie", icon: "faceid", accent: Brand.blue)
                credentialRow(.taxId, title: "Tax ID + address match", subtitle: "Validate your \(country.taxLabel) against the registry", icon: "checkmark.seal.fill", accent: Brand.success)
            }

            WizardCard {
                cardTitle("\(mode.label) operating credentials", icon: mode.icon)
                ForEach(branchedCredentials, id: \.self) { cred in
                    credentialRow(cred,
                                  title: cred.title,
                                  subtitle: cred.subtitle,
                                  icon: cred.icon,
                                  accent: cred.accent)
                }
            }

            if isCrossBorder {
                WizardCard {
                    cardTitle("Cross-border", icon: "globe.americas.fill")
                    credentialRow(.trustedTrader, title: "Trusted-trader program",
                                  subtitle: "CTPAT · PIP · OEA · FAST", icon: "shield.lefthalf.filled", accent: Brand.escort)
                }
            }

            WizardCard {
                cardTitle("Vertical endorsements", icon: "exclamationmark.triangle.fill")
                Text("Add a hazmat, oversize, FSMA, or other vertical endorsement if your freight requires it.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                credentialRow(.vertical, title: "Add an endorsement",
                              subtitle: "Hazmat · Oversize · FSMA · …", icon: "plus.diamond.fill", accent: Brand.hazmat)
            }
        }
    }

    /// Mode/country-specific operating credentials surfaced in step 2.
    private var branchedCredentials: [CredentialSheet] {
        switch mode {
        case .truck:  return [.operatingAuthority, .insuranceCOI, .clearinghouse]
        case .vessel: return [.maritimeCert]
        case .rail:   return [.railCert, .uiia]
        }
    }

    // MARK: Step 3 — Tier 2 (UBO + signers)

    private var tier2Step: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            WizardCard {
                cardTitle("Beneficial owners (Tier 2)", icon: "person.2.badge.key.fill")
                Text("List everyone who owns 25%+ of the company, plus an authorized signer. This unlocks transacting.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WizardCard {
                cardTitle("Ultimate beneficial owners", icon: "person.crop.circle.badge.checkmark")
                ForEach(ubos.indices, id: \.self) { i in
                    uboEditor(index: i)
                    if i < ubos.count - 1 { IridescentHairline().opacity(0.4) }
                }
                addRowButton(title: "Add another owner") { ubos.append(DraftUBO()) }
            }

            WizardCard {
                cardTitle("Authorized signer", icon: "signature")
                ForEach(signers.indices, id: \.self) { i in
                    signerEditor(index: i)
                    if i < signers.count - 1 { IridescentHairline().opacity(0.4) }
                }
                addRowButton(title: "Add another signer") { signers.append(DraftSigner()) }
            }

            if let err = tier2Error { WizardCard { errorLine(err) } }

            CTAButton(
                title: tier2Submitting ? "Submitting…" : "Start Tier 2 →",
                action: { Task { await runTier2() } },
                isLoading: tier2Submitting
            )
            .opacity(canRunTier2 ? 1 : 0.5)
            .allowsHitTesting(canRunTier2 && !tier2Submitting)
        }
    }

    // MARK: Step 4 — Tier 3 (escalation)

    private var tier3Step: some View {
        WizardCard {
            cardTitle("Cross-border / Hazmat (Tier 3)", icon: "shield.checkerboard")
            Text("Request the highest tier when you'll move hazmat or cross an international border. A compliance officer reviews this manually.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            fieldLabel("Reason")
            WizardField(text: $tier3Reason, placeholder: "e.g. Hazmat class 3 to Laredo, MX")

            fieldLabel("Notes (optional)")
            WizardField(text: $tier3Notes, placeholder: "Anything the reviewer should know", axisVertical: true)

            if let err = tier3Error { errorLine(err) }

            CTAButton(
                title: tier3Submitting ? "Requesting…" : "Request Tier 3 →",
                action: { Task { await runTier3() } },
                isLoading: tier3Submitting
            )
            .opacity(canRunTier3 ? 1 : 0.5)
            .allowsHitTesting(canRunTier3 && !tier3Submitting)
        }
    }

    // MARK: Tier ladder (0 → 3)

    private var tierLadder: some View {
        WizardCard {
            cardTitle("Tier progress", icon: "chart.bar.doc.horizontal.fill")
            ForEach(RiosTier.allCases, id: \.rawValue) { tier in
                tierRow(tier)
                if tier != RiosTier.allCases.last { IridescentHairline().opacity(0.35) }
            }
            if let p = progress, let msg = p.message, !msg.isEmpty {
                Text(msg)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            let blocking = (progress?.gates ?? []).filter { $0.isBlocking }
            if !blocking.isEmpty {
                inlineNote(icon: "lock.fill",
                           text: "\(blocking.count) gate\(blocking.count == 1 ? "" : "s") blocking the next tier — see Business / Owners above.",
                           tint: Brand.warning)
            }
        }
    }

    private func tierRow(_ tier: RiosTier) -> some View {
        let achieved = currentTier
        let isDone = tier.rawValue <= achieved
        let isCurrent = tier.rawValue == achieved
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isDone ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.bgCardSoft))
                    .frame(width: 30, height: 30)
                Image(systemName: isDone ? "checkmark" : "\(tier.rawValue).circle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isDone ? Color.white : palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(tier.label)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(tier.name)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            if isCurrent {
                StatusPill(text: "Current", kind: .info)
            } else if isDone {
                StatusPill(text: "Cleared", kind: .success)
            }
        }
        .padding(.vertical, 6)
    }

    /// Highest tier achieved per the server's TierProgress. Falls back to 0.
    private var currentTier: Int {
        guard let p = progress else { return 0 }
        return p.tier ?? p.kybTier ?? 0
    }

    // MARK: Footer nav (advance / retreat)

    private var navButtons: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Text("Back")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft))
                }
                .buttonStyle(.plain)
            }
            if step < stepTitles.count - 1 {
                CTAButton(title: step == stepTitles.count - 2 ? "Finish setup" : "Continue") {
                    withAnimation { step += 1 }
                }
            } else {
                CTAButton(title: "Done") { (onClose ?? { dismiss() })() }
            }
        }
    }

    // MARK: Credential row + sheet plumbing

    private func credentialRow(_ cred: CredentialSheet, title: String, subtitle: String, icon: String, accent: Color) -> some View {
        Button {
            activeSheet = cred
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    if let outcome = captureOutcomes[cred.rawValue] {
                        outcomeLine(outcome)
                    } else {
                        Text(subtitle).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Honest per-credential outcome line — never green unless cleared.
    private func outcomeLine(_ outcome: CaptureOutcome) -> some View {
        HStack(spacing: 5) {
            Image(systemName: outcome.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(outcome.tint)
            Text(outcome.text)
                .font(EType.caption)
                .foregroundStyle(outcome.tint)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: CredentialSheet) -> some View {
        switch sheet {
        case .idv:
            IDVLivenessSheet(userId: userId, country: country.rawValue) { status in
                captureOutcomes[sheet.rawValue] = CaptureOutcome(idvStatus: status)
            }
        case .taxId:
            TaxIDValidationSheet(userId: userId) { taxResult, addrResult in
                captureOutcomes[sheet.rawValue] = CaptureOutcome(tax: taxResult, address: addrResult)
            }
        case .operatingAuthority:
            OperatingAuthoritySheet(theme: palette, onClose: { activeSheet = nil })
        case .insuranceCOI:
            InsuranceCOIViewer(theme: palette, companyId: companyId)
        case .clearinghouse:
            ClearinghouseQuerySheet(driverId: userId ?? 0, driverName: session.user?.name)
        case .maritimeCert:
            MaritimeCertSheet(ownerEntityId: companyId ?? userId ?? 0,
                              ownerEntityType: "company",
                              onAttached: { result in
                                  captureOutcomes[sheet.rawValue] = CaptureOutcome(attach: result)
                              },
                              onClose: { activeSheet = nil })
        case .railCert:
            RailCertSheet(ownerEntityId: userId ?? 0) { result in
                captureOutcomes[sheet.rawValue] = CaptureOutcome(attach: result)
            }
        case .uiia:
            UIIAStatusSheet(companyId: companyId ?? 0, onClose: { activeSheet = nil })
        case .trustedTrader:
            TrustedTraderSheet(companyId: companyId, onClose: { activeSheet = nil })
        case .vertical:
            VerticalEndorsementSheet(theme: palette,
                                     entityId: companyId ?? userId ?? 0,
                                     entityType: "company") { result in
                captureOutcomes[sheet.rawValue] = CaptureOutcome(attach: result)
            }
        }
    }

    // MARK: UBO / signer editors

    private func uboEditor(index i: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Owner \(i + 1)").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                if ubos.count > 1 {
                    Button { ubos.remove(at: i) } label: {
                        Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Brand.danger)
                    }.buttonStyle(.plain)
                }
            }
            WizardField(text: $ubos[i].fullName, placeholder: "Full legal name")
            HStack(spacing: 8) {
                WizardField(text: $ubos[i].ownershipPercent, placeholder: "% owned", keyboard: .decimalPad)
                WizardField(text: $ubos[i].residenceCountry, placeholder: "Residence (US)", autocapitalize: .characters)
            }
            Toggle(isOn: $ubos[i].isControlPerson) {
                Text("Control person").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            .tint(Brand.blue)
        }
        .padding(.vertical, 4)
    }

    private func signerEditor(index i: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("Signer \(i + 1)").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                if signers.count > 1 {
                    Button { signers.remove(at: i) } label: {
                        Image(systemName: "trash").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Brand.danger)
                    }.buttonStyle(.plain)
                }
            }
            WizardField(text: $signers[i].fullName, placeholder: "Full legal name")
            WizardField(text: $signers[i].title, placeholder: "Title (e.g. Owner / CEO)")
        }
        .padding(.vertical, 4)
    }

    private func addRowButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 14, weight: .semibold))
                Text(title).font(EType.bodyStrong)
            }
            .foregroundStyle(LinearGradient.diagonal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: Gate rendering (honest states)

    private func gateList(_ gates: [RiosComplianceGate], heading: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(heading)
            if gates.isEmpty {
                Text("No gates returned.").font(EType.caption).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(gates) { gate in
                    gateRow(gate)
                }
            }
        }
        .padding(.top, 4)
    }

    private func gateRow(_ gate: RiosComplianceGate) -> some View {
        let g = GateState(status: gate.status)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: g.icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(g.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(gate.label ?? gate.gateId ?? "Gate")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
                if let detail = gate.detail, !detail.isEmpty {
                    Text(detail).font(EType.micro).foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            StatusPill(text: g.label(raw: gate.status), kind: g.pillKind)
        }
        .padding(.vertical, 3)
    }

    // MARK: API calls

    private func seedFromSession() {
        if companyName.isEmpty, let n = session.user?.name { companyName = n }
        // Seed mode/country from the role family.
        switch role {
        case .railEngineer, .railConductor, .railShipper, .railCatalyst, .railDispatch, .railBroker:
            mode = .rail
        case .vesselOperator, .vesselShipper, .shipCaptain, .portMaster, .vesselBroker, .customsBroker:
            mode = .vessel
        default:
            mode = .truck
        }
    }

    private var canRunTier1: Bool {
        !companyName.trimmingCharacters(in: .whitespaces).isEmpty
            && !taxId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runTier1() async {
        guard canRunTier1 else { return }
        tier1Submitting = true
        tier1Error = nil
        do {
            progress = try await EusoTripAPI.shared.registration.startTier1(
                companyName: companyName.trimmingCharacters(in: .whitespaces),
                taxId: taxId.trimmingCharacters(in: .whitespaces),
                country: country.rawValue,
                companyId: companyId
            )
            withAnimation { step = 2 }
        } catch {
            tier1Error = errorText(error)
        }
        tier1Submitting = false
    }

    private var canRunTier2: Bool {
        guard let cid = companyId, cid > 0 else { return false }
        let hasOwner = ubos.contains { !$0.fullName.trimmingCharacters(in: .whitespaces).isEmpty }
        let hasSigner = signers.contains { !$0.fullName.trimmingCharacters(in: .whitespaces).isEmpty }
        return hasOwner && hasSigner
    }

    private func runTier2() async {
        guard let cid = companyId, cid > 0 else {
            tier2Error = "We couldn't resolve your company. Finish Tier 1 first."
            return
        }
        tier2Submitting = true
        tier2Error = nil
        let uboPayload: [RegistrationAPI.UBO] = ubos
            .filter { !$0.fullName.trimmingCharacters(in: .whitespaces).isEmpty }
            .map {
                RegistrationAPI.UBO(
                    fullName: $0.fullName.trimmingCharacters(in: .whitespaces),
                    ownershipPercent: Double($0.ownershipPercent.trimmingCharacters(in: .whitespaces)),
                    dob: nil,
                    residenceCountry: $0.residenceCountry.isEmpty ? country.rawValue : $0.residenceCountry,
                    isOfficer: nil,
                    isControlPerson: $0.isControlPerson
                )
            }
        let signerPayload: [RegistrationAPI.Signer] = signers
            .filter { !$0.fullName.trimmingCharacters(in: .whitespaces).isEmpty }
            .map {
                RegistrationAPI.Signer(
                    fullName: $0.fullName.trimmingCharacters(in: .whitespaces),
                    title: $0.title.isEmpty ? nil : $0.title,
                    userId: userId,
                    docImageRef: nil,
                    selfieRef: nil,
                    country: country.rawValue
                )
            }
        do {
            progress = try await EusoTripAPI.shared.registration.startTier2(
                companyId: cid, ubos: uboPayload, signers: signerPayload, bankToken: nil
            )
            if isCrossBorder {
                withAnimation { step = 4 }
            }
        } catch {
            tier2Error = errorText(error)
        }
        tier2Submitting = false
    }

    private var canRunTier3: Bool {
        !tier3Reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runTier3() async {
        guard canRunTier3 else { return }
        tier3Submitting = true
        tier3Error = nil
        do {
            progress = try await EusoTripAPI.shared.registration.requestTier3(
                reason: tier3Reason.trimmingCharacters(in: .whitespaces),
                companyId: companyId,
                notes: tier3Notes.isEmpty ? nil : tier3Notes
            )
        } catch {
            tier3Error = errorText(error)
        }
        tier3Submitting = false
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? (error as? EusoTripAPIError)?.errorDescription
            ?? error.localizedDescription
    }

    private var isCrossBorder: Bool { country != .us }

    // MARK: Small shared UI helpers

    private func cardTitle(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text).font(EType.title).foregroundStyle(palette.textPrimary)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(EType.micro).tracking(0.6)
            .foregroundStyle(palette.textTertiary)
            .padding(.top, 4)
    }

    private func errorLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.danger)
            Text(text).font(EType.caption).foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func inlineNote(icon: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            Text(text).font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(tint.opacity(0.10)))
    }

    private func segChip(title: String, icon: String?, accent: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(EType.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.white : palette.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(selected ? AnyShapeStyle(accent) : AnyShapeStyle(palette.bgCardSoft))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(selected ? accent : palette.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Credential sheet enum

private enum CredentialSheet: String, Identifiable {
    case idv, taxId
    case operatingAuthority, insuranceCOI, clearinghouse
    case maritimeCert
    case railCert, uiia
    case trustedTrader
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idv:                return "ID + liveness check"
        case .taxId:              return "Tax ID + address match"
        case .operatingAuthority: return "Operating authority"
        case .insuranceCOI:       return "Insurance COI"
        case .clearinghouse:      return "Clearinghouse consent"
        case .maritimeCert:       return "Maritime certificate"
        case .railCert:           return "Rail certification"
        case .uiia:               return "UIIA interchange"
        case .trustedTrader:      return "Trusted-trader program"
        case .vertical:           return "Vertical endorsement"
        }
    }
    var subtitle: String {
        switch self {
        case .idv:                return "Scan a government ID, then a selfie"
        case .taxId:              return "Validate against the registry"
        case .operatingAuthority: return "MC / DOT / NSC operating authority"
        case .insuranceCOI:       return "Certificate of insurance"
        case .clearinghouse:      return "FMCSA drug & alcohol consent"
        case .maritimeCert:       return "DOC · SMC · ISSC · MMC"
        case .railCert:           return "FRA certification"
        case .uiia:               return "IANA equipment interchange"
        case .trustedTrader:      return "CTPAT · PIP · OEA · FAST"
        case .vertical:           return "Hazmat · Oversize · FSMA · …"
        }
    }
    var icon: String {
        switch self {
        case .idv:                return "faceid"
        case .taxId:              return "checkmark.seal.fill"
        case .operatingAuthority: return "doc.badge.gearshape.fill"
        case .insuranceCOI:       return "shield.fill"
        case .clearinghouse:      return "cross.case.fill"
        case .maritimeCert:       return "ferry.fill"
        case .railCert:           return "tram.fill"
        case .uiia:               return "shippingbox.fill"
        case .trustedTrader:      return "shield.lefthalf.filled"
        case .vertical:           return "exclamationmark.triangle.fill"
        }
    }
    var accent: Color {
        switch self {
        case .idv:                return Brand.blue
        case .taxId:              return Brand.success
        case .operatingAuthority: return Brand.blue
        case .insuranceCOI:       return Brand.info
        case .clearinghouse:      return Brand.danger
        case .maritimeCert:       return Brand.vessel
        case .railCert:           return Brand.rail
        case .uiia:               return Brand.rail
        case .trustedTrader:      return Brand.escort
        case .vertical:           return Brand.hazmat
        }
    }
}

// MARK: - Draft models for Tier 2 editors

private struct DraftUBO {
    var fullName: String = ""
    var ownershipPercent: String = ""
    var residenceCountry: String = ""
    var isControlPerson: Bool = false
}

private struct DraftSigner {
    var fullName: String = ""
    var title: String = ""
}

// MARK: - Honest capture outcome (per credential)

/// Renders a credential capture / attach result honestly. Green only on a
/// server-confirmed clear/verified state; pending / provider_unavailable /
/// null / unknown all collapse to neutral amber; thrown errors are red.
private struct CaptureOutcome {
    let text: String
    let tint: Color
    let icon: String

    private static let clearStates: Set<String> =
        ["verified", "clear", "active", "approved", "attached", "valid", "pass", "passed", "true"]

    /// From kyc.runIDV / runLiveness verdict string.
    init(idvStatus: String) {
        let raw = idvStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = raw.lowercased()
        if Self.clearStates.contains(n) {
            self.init(text: "Verified", tint: Brand.success, icon: "checkmark.seal.fill")
        } else if n == "failed" {
            self.init(text: "Verification failed — retry or contact support", tint: Brand.danger, icon: "xmark.octagon.fill")
        } else if n == "incomplete" {
            self.init(text: "Not finished — re-open to complete", tint: Brand.warning, icon: "clock.fill")
        } else {
            self.init(text: "Pending review (\(raw.isEmpty ? "pending" : raw))", tint: Brand.warning, icon: "clock.fill")
        }
    }

    /// From kyc.matchTaxId (+ optional address validation).
    init(tax: KycAPI.TaxIdResult, address: KycAPI.AddressResult?) {
        let addrSuffix: String = {
            guard let a = address else { return "" }
            if a.verified == true { return " · address verified" }
            return " · address pending"
        }()
        switch tax.valid {
        case .some(true):
            self.init(text: "Tax ID matched\(addrSuffix)", tint: Brand.success, icon: "checkmark.seal.fill")
        case .some(false):
            let msg = tax.message?.isEmpty == false ? tax.message! : "Tax ID did not match the registry"
            self.init(text: msg, tint: Brand.danger, icon: "xmark.octagon.fill")
        case .none:
            // null valid = registry validator unavailable → manual review.
            self.init(text: "Provider unavailable — manual review\(addrSuffix)", tint: Brand.warning, icon: "clock.fill")
        }
    }

    /// From any registration.attach* AttachResult.
    init(attach: RegistrationAPI.AttachResult) {
        let raw = (attach.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let n = raw.lowercased()
        if Self.clearStates.contains(n) {
            let exp = attach.expiresAt.map { " · expires \($0.prefix(10))" } ?? ""
            self.init(text: "Attached\(exp)", tint: Brand.success, icon: "checkmark.seal.fill")
        } else if n == "failed" || n == "rejected" {
            self.init(text: "Rejected — \(attach.warnings?.first ?? "see details")", tint: Brand.danger, icon: "xmark.octagon.fill")
        } else {
            self.init(text: "Pending review (\(raw.isEmpty ? "pending" : raw))", tint: Brand.warning, icon: "clock.fill")
        }
    }

    private init(text: String, tint: Color, icon: String) {
        self.text = text
        self.tint = tint
        self.icon = icon
    }
}

// MARK: - Honest gate state (maps a server gate status to a pill)

private struct GateState {
    let icon: String
    let tint: Color
    let pillKind: StatusPill.Kind

    init(status: String?) {
        let n = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch n {
        case "pass", "passed", "verified", "clear", "cleared", "active", "ok":
            icon = "checkmark.circle.fill"; tint = Brand.success; pillKind = .success
        case "blocked", "failed", "rejected":
            icon = "xmark.octagon.fill"; tint = Brand.danger; pillKind = .danger
        default:
            // pending / provider_unavailable / null / unknown → neutral amber.
            icon = "clock.fill"; tint = Brand.warning; pillKind = .warning
        }
    }

    func label(raw: String?) -> String {
        let r = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? "Pending" : r
    }
}

// MARK: - Local field + card primitives (no DesignSystem GlassField dependency)

/// Bespoke text field — palette-tinted, gradient-focus hairline. Built inline
/// from SwiftUI primitives + design tokens so the wizard doesn't depend on a
/// component whose signature we haven't verified.
private struct WizardField: View {
    @Binding var text: String
    var placeholder: String
    var keyboard: UIKeyboardType = .default
    var autocapitalize: TextInputAutocapitalization = .sentences
    var axisVertical: Bool = false

    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if axisVertical {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2...4)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(EType.body)
        .foregroundStyle(palette.textPrimary)
        .keyboardType(keyboard)
        .textInputAutocapitalization(autocapitalize)
        // TextInputAutocapitalization isn't Equatable; key autocorrect off
        // the keyboard type instead (numeric/ascii ID fields → no autocorrect).
        .autocorrectionDisabled(keyboard != .default)
        .focused($focused)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(palette.bgCardSoft))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(focused ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderSoft),
                              lineWidth: focused ? 1.4 : 1)
        )
    }
}

/// Standard card surface for the wizard — leans on the canonical `.eusoCard`
/// modifier so it matches the rest of the app.
private struct WizardCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            content()
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }
}

// MARK: - Previews

#Preview("1111 · Onboarding wizard · Night") {
    OnboardingWizard(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("1111 · Onboarding wizard · Afternoon") {
    OnboardingWizard(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
