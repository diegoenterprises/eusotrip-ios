//
//  002_CreateAccount.swift
//  EusoTrip — Multi-modal registration wizard (web /register parity).
//
//  Mirrors `frontend/client/src/pages/Register.tsx` 1:1:
//    Step 1  Country         (multi-select · US / CA / MX)
//    Step 2  Transport Mode  (multi-select · TRUCK / RAIL / VESSEL)
//    Step 3  Role            (filtered by selected modes)
//    Step 4  Role-specific form + T&C / Privacy acceptance
//    Step 5  Verify email card
//
//  Design DNA pulled from the Driver·Dark Figma canvas: aurora-lit dark base,
//  glass surfaces with blue→magenta iridescent rims, rounded pill CTAs,
//  ALL-CAPS tracking micro-labels, Brand.blue 0x1473FF → Brand.magenta 0xBE01FF.
//

import SwiftUI

struct CreateAccountView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: EusoTripSession
    @StateObject private var vm = RegistrationViewModel()
    @Namespace private var stepNS
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case first, last, email, phone, password, confirm
        case company, mc, dot, ein, bondProv, bondAmt
        case cdl, cdlState, dob, companyCode
        case brokerMC, certState, certExp
        case addr, city, state, zip
        // 4-new-role parity fields (Terminal / Compliance / Safety /
        // Admin). Listed here so `focused()` can target them just
        // like every other input on the wizard.
        case facilityName, epaFacilityId
        case certNumber, trainingProvider, trainingCompletionDate
        case csaCert, yearsExperience
        case inviteCode
    }

    /// Wizard position. `.form` and `.verifyEmailSent` are shared across all roles.
    enum Step: Int, CaseIterable { case country, mode, role, form, verifyEmailSent }

    @State private var step: Step = .country
    @State private var showTerms = false
    @State private var showPrivacy = false

    // Carrier-only post-signup "While you wait" kickstart sheets.
    // Solo roles don't see the row so these stay false for them.
    @State private var showFleetSetup = false
    @State private var showInviteTeam = false

    // MARK: Body

    var body: some View {
        ZStack {
            AuroraBackground()
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }
            ScrollView {
                // TileStack — registration wizard reveals header → step
                // progress → step content → helper footer in a staggered
                // cascade every time the wizard advances.
                TileStack(spacing: Space.s6) {
                    header
                    stepProgress
                    stepContent
                    helperFooter
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s6)
                .padding(.bottom, Space.s8)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            closeButton
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
        .animation(.easeOut(duration: 0.2), value: vm.phase)
        .sheet(isPresented: $showTerms) { TermsOfServiceView().eusoSheet() }
        .sheet(isPresented: $showPrivacy) { PrivacyPolicyView().eusoSheet() }
        .onChange(of: vm.phase) { _, new in
            if case .success = new { step = .verifyEmailSent }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.s4) {
            GradientLogo(size: 88)
            VStack(spacing: 6) {
                Text(heroTitle)
                    .font(EType.h1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textPrimary)
                if let accent = heroAccent {
                    Text(accent)
                        .font(EType.h1)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(heroSubtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            IridescentHairline().padding(.top, Space.s2)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroTitle: String {
        switch step {
        case .country:         return "Join the Future of"
        case .mode:            return "Pick your transport modes"
        case .role:            return "Choose your role"
        case .form:            return "Create your"
        case .verifyEmailSent: return "Verify your email"
        }
    }

    private var heroAccent: String? {
        switch step {
        case .country: return "Freight & Energy Logistics"
        case .form:    return "\(vm.role.displayName) account"
        default:       return nil
        }
    }

    private var heroSubtitle: String {
        switch step {
        case .country:         return "Select your operating country. Multi-select allowed for cross-border operators."
        case .mode:            return "Select your transport mode(s). Multi-select allowed for multi-modal operators."
        case .role:            return "Select your role to begin registration. Each role has specific regulatory requirements."
        case .form:            return vm.role.tagline
        case .verifyEmailSent: return "Last step — we sent you a link."
        }
    }

    // MARK: Step progress

    private var stepProgress: some View {
        HStack(spacing: 8) {
            ForEach([Step.country, .mode, .role], id: \.self) { s in
                stepPill(for: s)
                if s != .role {
                    Rectangle()
                        .fill(s.rawValue < step.rawValue
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.borderFaint))
                        .frame(width: 44, height: 2)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -Space.s2)
        .opacity(step == .form || step == .verifyEmailSent ? 0 : 1)
    }

    private func stepPill(for s: Step) -> some View {
        let isDone = s.rawValue < step.rawValue
        let isCurrent = s == step
        return ZStack {
            Circle()
                .fill(
                    isDone ? AnyShapeStyle(LinearGradient.diagonal) :
                    isCurrent ? AnyShapeStyle(LinearGradient.diagonal) :
                    AnyShapeStyle(palette.bgCardSoft.opacity(0.8))
                )
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().strokeBorder(
                        isCurrent || isDone ? Color.clear : palette.borderSoft,
                        lineWidth: 1
                    )
                )
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(String(s.rawValue + 1))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isCurrent ? .white : palette.textTertiary)
            }
        }
    }

    // MARK: Step router

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .country:         countryStep
        case .mode:            modeStep
        case .role:            roleStep
        case .form:            GlassCard { formContent }
        case .verifyEmailSent: verifyEmailCard
        }
    }

    // MARK: Step 1 — Country

    private var countryStep: some View {
        VStack(spacing: Space.s4) {
            VStack(spacing: Space.s3) {
                ForEach(RegistrationCountry.allCases) { c in
                    countryCard(c)
                }
            }
            primaryCTA(title: "Continue",
                       enabled: !vm.selectedCountries.isEmpty,
                       action: { withAnimation { step = .mode } })
        }
    }

    private func countryCard(_ c: RegistrationCountry) -> some View {
        let selected = vm.selectedCountries.contains(c)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                vm.toggleCountry(c)
            }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(selected ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                                       : AnyShapeStyle(palette.bgCardSoft.opacity(0.7)))
                    Text(c.flagEmoji).font(.system(size: 28))
                }
                .frame(width: 56, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.displayName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(c.regulatoryBlurb)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                checkmarkPill(selected: selected)
            }
            .padding(Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(selected ? palette.bgCard.opacity(0.95) : palette.bgCardSoft.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        selected ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.6))
                                 : AnyShapeStyle(palette.borderFaint),
                        lineWidth: selected ? 1.2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 2 — Mode

    private var modeStep: some View {
        VStack(spacing: Space.s4) {
            VStack(spacing: Space.s3) {
                ForEach(TransportMode.allCases) { m in
                    modeCard(m)
                }
            }
            HStack(spacing: Space.s3) {
                secondaryButton(title: "Back",
                                icon: "chevron.left",
                                action: { withAnimation { step = .country } })
                primaryCTA(title: "Continue",
                           enabled: !vm.selectedModes.isEmpty,
                           action: { withAnimation { step = .role } })
            }
        }
    }

    private func modeCard(_ m: TransportMode) -> some View {
        let selected = vm.selectedModes.contains(m)
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                vm.toggleMode(m)
            }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(selected ? AnyShapeStyle(LinearGradient.diagonal)
                                       : AnyShapeStyle(palette.tintNeutral))
                    Image(systemName: m.iconSystemName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : palette.textPrimary)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.registrationDisplayName)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(m.tagline)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                checkmarkPill(selected: selected)
            }
            .padding(Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(selected ? palette.bgCard.opacity(0.95) : palette.bgCardSoft.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        selected ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.6))
                                 : AnyShapeStyle(palette.borderFaint),
                        lineWidth: selected ? 1.2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Step 3 — Role

    private var roleStep: some View {
        VStack(spacing: Space.s4) {
            complianceNotice

            // Selected tags recap
            FlowLayout(spacing: 6) {
                // Gradient tag pills — doctrine §2.1 (gradient, not blue/magenta fills).
                ForEach(Array(vm.selectedCountries)) { c in
                    gradientTagPill(text: "\(c.flagEmoji) \(c.displayName)")
                }
                ForEach(Array(vm.selectedModes)) { m in
                    gradientTagPill(text: m.registrationDisplayName)
                }
            }

            // Role grid (1 column · stacked, iOS friendly)
            VStack(spacing: Space.s3) {
                ForEach(vm.rolesForSelectedModes) { r in
                    roleCard(r)
                }
            }

            HStack(spacing: Space.s3) {
                secondaryButton(title: "Back",
                                icon: "chevron.left",
                                action: { withAnimation { step = .mode } })
                primaryCTA(title: "Continue as \(vm.role.displayName)",
                           enabled: !vm.role.isInviteOnly,
                           action: { withAnimation { step = .form } })
            }
        }
    }

    private var complianceNotice: some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18))
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Regulatory Compliance Verified")
                    .font(EType.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("EusoTrip automatically verifies FMCSA, PHMSA, TSA, FRA, FMC, USCG, and state requirements during registration. All data is encrypted and stored per DOT 49 CFR standards.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.diagonal.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1)
        )
    }

    private func roleCard(_ r: EusoRole) -> some View {
        let selected = r == vm.role
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                vm.role = r
            }
        } label: {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(selected ? AnyShapeStyle(LinearGradient.diagonal)
                                           : AnyShapeStyle(palette.tintNeutral))
                        Image(systemName: r.iconSystemName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : palette.textPrimary)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(r.displayName)
                                .font(EType.bodyStrong)
                                .foregroundStyle(palette.textPrimary)
                            if r.isInviteOnly {
                                Text("INVITE ONLY")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.8)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(palette.textTertiary)
                                    .background(palette.bgCardSoft.opacity(0.8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(palette.borderSoft)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        Text(r.shortDescription)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    checkmarkPill(selected: selected)
                }

                // Mode badges
                HStack(spacing: 4) {
                    ForEach(Array(r.modes).sorted(by: { $0.rawValue < $1.rawValue })) { m in
                        Image(systemName: m.iconSystemName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(modeBadgeColor(m))
                            .frame(width: 20, height: 20)
                            .background(modeBadgeColor(m).opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer(minLength: 0)
                }

                if selected {
                    Divider().overlay(palette.borderFaint)
                    // Requirements
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REQUIREMENTS")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        FlowLayout(spacing: 6) {
                            ForEach(r.requirements.prefix(3), id: \.self) { req in
                                tagPill(text: req, color: palette.textSecondary, subtle: true)
                            }
                            if r.requirements.count > 3 {
                                tagPill(text: "+\(r.requirements.count - 3) more",
                                        color: palette.textTertiary, subtle: true)
                            }
                        }
                    }
                    // Regulations
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REGULATORY BODIES")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        FlowLayout(spacing: 6) {
                            // Gradient tag pills — doctrine §2.1.
                            ForEach(r.regulations, id: \.self) { reg in
                                gradientTagPill(text: reg)
                            }
                        }
                    }
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(selected ? palette.bgCard.opacity(0.95) : palette.bgCardSoft.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(
                        selected ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.65))
                                 : AnyShapeStyle(palette.borderFaint),
                        lineWidth: selected ? 1.25 : 1
                    )
            )
            .opacity(r.isInviteOnly ? 0.65 : 1)
        }
        .buttonStyle(.plain)
        .disabled(r.isInviteOnly)
    }

    // Doctrine §2.1 carve-out: transport-mode badge colors must be distinguishable
    // from each other (truck orange · rail blue · vessel teal). Here Brand.blue is
    // acting as the *rail* semantic accent, not as a primary fill — swapping it for
    // the brand gradient would collapse the three-mode visual differentiation.
    // Leave as-is. Reviewed 2026-04-20.
    private func modeBadgeColor(_ m: TransportMode) -> Color {
        switch m {
        case .truck:  return Color(red: 0.976, green: 0.451, blue: 0.086)
        case .rail:   return Brand.blue
        case .vessel: return Color(red: 0.024, green: 0.714, blue: 0.831)
        case .barge:  return Brand.info
        }
    }

    // MARK: Step 4 — Role-specific form

    @ViewBuilder
    private var formContent: some View {
        if !vm.role.isSignupImplemented {
            waitlistContent
        } else {
            implementedFormContent
        }
    }

    /// Waitlist card for rail / vessel / factoring / super-admin roles
    /// whose backend registration procs haven't shipped yet. Matches
    /// the web's state — the UI exists, but submission isn't wired —
    /// without letting the driver hit Submit and get a server error.
    /// Prompts them to email support so our team can either issue an
    /// invite code or ping them the minute the role opens.
    @ViewBuilder
    private var waitlistContent: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            backStrip

            HStack(spacing: Space.s3) {
                Image(systemName: vm.role.iconSystemName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.role.displayName)
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.role.tagline)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Opening soon")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
                Text("This role is on our roadmap — the surfaces are being wired against the same compliance and payout rails the truck side uses today. To claim your spot early, email us and we'll either fast-track you with an invite code or notify you the moment this role opens to self-sign-up.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Requirements preview so the user knows what they'll need
            // the day the role opens. Reads off the same `requirements`
            // array the web uses — zero fake copy.
            if !vm.role.requirements.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("YOU'LL NEED")
                        .font(EType.micro)
                        .tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(vm.role.requirements, id: \.self) { req in
                            HStack(alignment: .top, spacing: Space.s2) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(palette.textTertiary)
                                    .padding(.top, 7)
                                Text(req)
                                    .font(EType.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                }
                .padding(Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft.opacity(0.6))
                )
            }

            // Email-support CTA — opens the mail composer with a
            // pre-filled subject so the team can triage fast. No
            // form submission, no silent API call.
            if let mailURL = URL(string: waitlistMailToURL(role: vm.role)) {
                Link(destination: mailURL) {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Email to join the waitlist")
                            .font(EType.bodyStrong)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }

            // Let them still back out to pick a different role.
            Button {
                withAnimation { step = .role }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(systemName: "arrow.left")
                    Text("Pick a different role")
                }
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.vertical, Space.s2)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    /// mailto: URL with subject + body pre-filled so the waitlist
    /// email lands with enough context that support can respond with
    /// an invite code or a heads-up without a back-and-forth.
    private func waitlistMailToURL(role: EusoRole) -> String {
        let subject = "Waitlist: \(role.displayName)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = [
            "I'd like early access to the \(role.displayName) role on EusoTrip.",
            "",
            "Name:",
            "Company:",
            "USDOT / MC / STB / FMC / USCG (as applicable):",
            "",
            "Please send an invite code or notify me when this role opens.",
        ].joined(separator: "\n")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "mailto:onboarding@eusotrip.com?subject=\(subject)&body=\(body)"
    }

    @ViewBuilder
    private var implementedFormContent: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            backStrip

            // Name row
            HStack(spacing: Space.s3) {
                GlassField(label: "First name", placeholder: "Alex", icon: "person",
                           text: $vm.firstName, textContentType: .givenName,
                           autocapitalization: .words)
                    .focused($focus, equals: .first)
                GlassField(label: "Last name", placeholder: "Rivera", icon: nil,
                           text: $vm.lastName, textContentType: .familyName,
                           autocapitalization: .words)
                    .focused($focus, equals: .last)
            }

            GlassField(label: "Email", placeholder: "you@company.com", icon: "envelope",
                       text: $vm.email, keyboardType: .emailAddress,
                       textContentType: .emailAddress, error: vm.emailError)
                .focused($focus, equals: .email)

            GlassField(label: "Phone (optional)", placeholder: "+1 555 0199",
                       icon: "phone",
                       text: $vm.phone, keyboardType: .phonePad,
                       textContentType: .telephoneNumber)
                .focused($focus, equals: .phone)

            GlassField(label: "Password", placeholder: "Minimum 8 characters",
                       icon: "lock",
                       text: $vm.password, isSecure: true,
                       textContentType: .newPassword,
                       error: vm.passwordStrengthMessage)
                .focused($focus, equals: .password)

            GlassField(label: "Confirm password", placeholder: "Repeat password",
                       icon: "lock.fill",
                       text: $vm.confirmPassword, isSecure: true,
                       textContentType: .newPassword,
                       error: vm.confirmPasswordMessage)
                .focused($focus, equals: .confirm)

            roleSpecificFields

            // T&C + Privacy
            GlassToggleRow(
                isOn: $vm.acceptsTerms,
                title: "I agree to the",
                linkTitle: "Terms of Service",
                linkTapped: { showTerms = true }
            )
            GlassToggleRow(
                isOn: $vm.acceptsPrivacy,
                title: "I agree to the",
                linkTitle: "Privacy Policy",
                linkTapped: { showPrivacy = true }
            )

            if case .error(let msg) = vm.phase { errorBanner(msg) }

            CTAButton(
                title: isSubmitting ? "Creating account…" : "Create account",
                action: { Task { await vm.submit() } }
            )
            .opacity(vm.canSubmit && !isSubmitting ? 1 : 0.55)
            .disabled(!vm.canSubmit || isSubmitting)
            .sensoryFeedback(.success, trigger: isSuccess)
        }
    }

    private var backStrip: some View {
        HStack(spacing: Space.s2) {
            Button {
                withAnimation { step = .role }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Change role")
                }
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: vm.role.iconSystemName)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(vm.role.displayName)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 6)
            .background(palette.bgCardSoft.opacity(0.7))
            .overlay(Capsule().strokeBorder(palette.borderSoft))
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var roleSpecificFields: some View {
        switch vm.role {
        case .driver:
            driverFields
        case .shipper:
            companyBlock(title: "Shipper company")
            addressBlock()
        case .catalyst:
            carrierFields
        case .broker:
            brokerFields
        case .dispatch, .railDispatch:
            GlassField(label: "Company invite code", placeholder: "Optional · from your carrier",
                       icon: "key.horizontal",
                       text: $vm.companyCode, autocapitalization: .characters)
                .focused($focus, equals: .companyCode)
        case .escort:
            GlassField(label: "Certification state", placeholder: "e.g. TX",
                       icon: "flag",
                       text: $vm.escortCertState, autocapitalization: .characters)
                .focused($focus, equals: .certState)
            GlassField(label: "Certification expires", placeholder: "YYYY-MM-DD",
                       icon: "calendar",
                       text: $vm.certificationExpires, keyboardType: .numbersAndPunctuation)
                .focused($focus, equals: .certExp)
        case .terminal:
            terminalFields
        case .compliance:
            complianceFields
        case .safety:
            safetyFields
        case .admin:
            adminFields
        case .superAdmin:
            superAdminFields
        // Rail
        case .railShipper:
            railShipperFields
        case .railCatalyst:
            railCatalystFields
        case .railBroker:
            railBrokerFields
        case .railEngineer, .railConductor:
            railCrewFields
        // Vessel
        case .vesselShipper:
            vesselShipperFields
        case .vesselOperator:
            vesselOperatorFields
        case .vesselBroker:
            vesselBrokerFields
        case .shipCaptain:
            shipCaptainFields
        case .portMaster:
            portMasterFields
        case .customsBroker:
            customsBrokerFields
        // Factoring
        case .factoring:
            factoringFields
        }
    }

    // MARK: - Super-Admin

    private var superAdminFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Super-Admin".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
            GlassField(label: "Invite code",
                       placeholder: "Super-admin-issued token",
                       icon: "key", text: $vm.inviteCode,
                       autocapitalization: .characters)
                .focused($focus, equals: .inviteCode)
            GlassField(label: "Reason (optional)",
                       placeholder: "What's this account for?",
                       icon: "doc.text",
                       text: $vm.superAdminReason, autocapitalization: .sentences)
        }
    }

    // MARK: - Rail roles

    private var railShipperFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Rail shipper company")
            GlassField(label: "EIN (optional)", placeholder: "XX-XXXXXXX",
                       icon: "building.columns",
                       text: $vm.ein, autocapitalization: .characters)
                .focused($focus, equals: .ein)
            GlassField(label: "STB registration (optional)",
                       placeholder: "Surface Transportation Board #",
                       icon: "tram.fill",
                       text: $vm.stbRegistration, autocapitalization: .characters)
        }
    }

    private var railCatalystFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Rail carrier")
            HStack(spacing: Space.s3) {
                GlassField(label: "STB docket #",
                           placeholder: "STB-FD-12345",
                           icon: "number",
                           text: $vm.stbDocket, autocapitalization: .characters)
                GlassField(label: "FRA cert (optional)",
                           placeholder: "FRA registration",
                           icon: "checkmark.shield",
                           text: $vm.fraCertification, autocapitalization: .characters)
            }
            HStack(spacing: Space.s3) {
                GlassField(label: "Locomotives",
                           placeholder: "Count",
                           icon: "tram",
                           text: $vm.locomotiveCount, keyboardType: .numberPad)
                GlassField(label: "Railcars",
                           placeholder: "Count",
                           icon: "number.square",
                           text: $vm.railcarCount, keyboardType: .numberPad)
            }
            GlassField(label: "EIN (optional)",
                       placeholder: "XX-XXXXXXX",
                       icon: "building.columns",
                       text: $vm.ein, autocapitalization: .characters)
        }
    }

    private var railBrokerFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Rail brokerage")
            HStack(spacing: Space.s3) {
                GlassField(label: "IMC registration",
                           placeholder: "Intermodal Marketing Co.",
                           icon: "arrow.triangle.branch",
                           text: $vm.imcRegistration, autocapitalization: .characters)
                GlassField(label: "STB reg.",
                           placeholder: "Optional",
                           icon: "tram.fill",
                           text: $vm.stbRegistration, autocapitalization: .characters)
            }
            HStack(spacing: Space.s3) {
                GlassField(label: "Bond provider (opt.)",
                           placeholder: "Company",
                           icon: "shield",
                           text: $vm.bondProvider, autocapitalization: .words)
                GlassField(label: "Bond amount",
                           placeholder: "75000",
                           icon: "dollarsign",
                           text: $vm.bondAmount, keyboardType: .decimalPad)
            }
        }
    }

    /// Shared form for RAIL_ENGINEER + RAIL_CONDUCTOR — both require the
    /// FRA certification number (49 CFR 240 + 242), only the CFR label
    /// differs. Medical + experience fields mirror what the truck-side
    /// driver form collects.
    private var railCrewFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("FRA certification".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)

            // FRA Part 240 (engineer) or Part 242 (conductor) cert
            // scan — auto-fills cert #, expiration, employer railroad,
            // and locomotive territory in one pass.
            CredentialScanCard(
                credentialType: vm.role == .railEngineer ? "fra_part240_engineer" : "fra_part242_conductor",
                title: vm.role == .railEngineer
                    ? "Scan your FRA engineer cert"
                    : "Scan your FRA conductor cert",
                subtitle: "Auto-fills cert #, expiration, employer railroad, and territory."
            ) { applyFRACert($0) }

            GlassField(label: "FRA cert #",
                       placeholder: vm.role == .railEngineer ? "§49 CFR 240" : "§49 CFR 242",
                       icon: "checkmark.shield.fill",
                       text: $vm.fraCertificationNumber, autocapitalization: .characters)
                .focused($focus, equals: .certNumber)
            HStack(spacing: Space.s3) {
                GlassField(label: "Expires",
                           placeholder: "YYYY-MM-DD",
                           icon: "calendar",
                           text: $vm.fraCertificationExpires, keyboardType: .numbersAndPunctuation)
                GlassField(label: "Years experience",
                           placeholder: "5",
                           icon: "number",
                           text: $vm.yearsOfExperience, keyboardType: .numberPad)
            }
            GlassField(label: "Employer railroad",
                       placeholder: "BNSF / Union Pacific / ...",
                       icon: "building.2",
                       text: $vm.employerRailroad, autocapitalization: .words)
            GlassField(label: "Date of birth (optional)",
                       placeholder: "YYYY-MM-DD",
                       icon: "calendar",
                       text: $vm.dateOfBirth, keyboardType: .numbersAndPunctuation)
                .focused($focus, equals: .dob)
        }
    }

    // MARK: - Vessel roles

    private var vesselShipperFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Vessel shipper")
            HStack(spacing: Space.s3) {
                GlassField(label: "FMC registration",
                           placeholder: "Federal Maritime Comm.",
                           icon: "ferry.fill",
                           text: $vm.fmcRegistration, autocapitalization: .characters)
                GlassField(label: "EIN (optional)",
                           placeholder: "XX-XXXXXXX",
                           icon: "building.columns",
                           text: $vm.ein, autocapitalization: .characters)
            }
        }
    }

    private var vesselOperatorFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Vessel operator")

            // USCG Certificate of Documentation scan — pulls official
            // number, vessel name, IMO #, call sign, hailing port.
            CredentialScanCard(
                credentialType: "uscg_vessel_doc",
                title: "Scan your USCG Certificate of Documentation",
                subtitle: "Auto-fills official #, vessel name, IMO, call sign, owner."
            ) { applyVesselDoc($0) }

            HStack(spacing: Space.s3) {
                GlassField(label: "FMC license",
                           placeholder: "OTI / VOCC",
                           icon: "ferry.fill",
                           text: $vm.fmcLicenseNumber, autocapitalization: .characters)
                GlassField(label: "USCG doc #",
                           placeholder: "Coast Guard",
                           icon: "checkmark.shield",
                           text: $vm.uscgDocumentNumber, autocapitalization: .characters)
            }
            GlassField(label: "Vessel count",
                       placeholder: "Fleet size",
                       icon: "number.square",
                       text: $vm.vesselCount, keyboardType: .numberPad)
        }
    }

    private var vesselBrokerFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Vessel brokerage")
            GlassField(label: "FMC license",
                       placeholder: "Federal Maritime Comm.",
                       icon: "ferry.fill",
                       text: $vm.fmcLicenseNumber, autocapitalization: .characters)
            HStack(spacing: Space.s3) {
                GlassField(label: "Bond provider (opt.)",
                           placeholder: "Company",
                           icon: "shield",
                           text: $vm.bondProvider, autocapitalization: .words)
                GlassField(label: "Bond amount",
                           placeholder: "75000",
                           icon: "dollarsign",
                           text: $vm.bondAmount, keyboardType: .decimalPad)
            }
        }
    }

    private var shipCaptainFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Merchant Mariner Credential".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)

            // USCG MMC scan — pulls mariner reference #, expiration,
            // GT capacity, route authorization, endorsements.
            CredentialScanCard(
                credentialType: "uscg_mmc",
                title: "Scan your USCG MMC",
                subtitle: "Auto-fills credential #, expiration, GT capacity, and route."
            ) { applyMMC($0) }

            GlassField(label: "MMC license #",
                       placeholder: "USCG-issued credential",
                       icon: "checkmark.shield.fill",
                       text: $vm.mmcLicenseNumber, autocapitalization: .characters)
            HStack(spacing: Space.s3) {
                GlassField(label: "MMC expires",
                           placeholder: "YYYY-MM-DD",
                           icon: "calendar",
                           text: $vm.mmcExpires, keyboardType: .numbersAndPunctuation)
                GlassField(label: "Years at sea",
                           placeholder: "10",
                           icon: "number",
                           text: $vm.yearsAtSea, keyboardType: .numberPad)
            }
            GlassField(label: "STCW cert (optional)",
                       placeholder: "Training cert #",
                       icon: "book.closed",
                       text: $vm.stcwCertification, autocapitalization: .characters)
            GlassField(label: "STCW expires",
                       placeholder: "YYYY-MM-DD",
                       icon: "calendar",
                       text: $vm.stcwExpires, keyboardType: .numbersAndPunctuation)
            GlassField(label: "Date of birth (optional)",
                       placeholder: "YYYY-MM-DD",
                       icon: "calendar",
                       text: $vm.dateOfBirth, keyboardType: .numbersAndPunctuation)
                .focused($focus, equals: .dob)
        }
    }

    private var portMasterFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Port / facility".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
            GlassField(label: "Port name",
                       placeholder: "Port of Houston",
                       icon: "ferry",
                       text: $vm.portName, autocapitalization: .words)
                .focused($focus, equals: .facilityName)
            GlassField(label: "Port authority (optional)",
                       placeholder: "Issuing body",
                       icon: "building.columns",
                       text: $vm.portAuthority, autocapitalization: .words)
            HStack(spacing: Space.s3) {
                GlassField(label: "MTSA plan (opt.)",
                           placeholder: "33 CFR 105",
                           icon: "lock.shield",
                           text: $vm.mtsaFacilityPlan, autocapitalization: .characters)
                GlassField(label: "USCG facility id",
                           placeholder: "Optional",
                           icon: "checkmark.shield",
                           text: $vm.uscgFacilityId, autocapitalization: .characters)
            }
        }
    }

    private var customsBrokerFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Customs brokerage")
            Text("CBP license · 19 CFR 111".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)

            // CBP Form 3124 customs broker license scan — pulls
            // license #, port of entry, examination date.
            CredentialScanCard(
                credentialType: "customs_broker_license",
                title: "Scan your CBP Form 3124 license",
                subtitle: "Auto-fills license #, port of entry, and examination date."
            ) { applyCBPLicense($0) }

            GlassField(label: "CBP license #",
                       placeholder: "Customs & Border Protection",
                       icon: "checkmark.shield.fill",
                       text: $vm.cbpLicenseNumber, autocapitalization: .characters)
            HStack(spacing: Space.s3) {
                GlassField(label: "License expires",
                           placeholder: "YYYY-MM-DD",
                           icon: "calendar",
                           text: $vm.cbpLicenseExpires, keyboardType: .numbersAndPunctuation)
                GlassField(label: "EIN (opt.)",
                           placeholder: "XX-XXXXXXX",
                           icon: "building.columns",
                           text: $vm.ein, autocapitalization: .characters)
            }
            HStack(spacing: Space.s3) {
                GlassField(label: "Bond #",
                           placeholder: "Optional",
                           icon: "shield",
                           text: $vm.bondNumber, autocapitalization: .characters)
                GlassField(label: "Bond amount",
                           placeholder: "50000",
                           icon: "dollarsign",
                           text: $vm.bondAmount, keyboardType: .decimalPad)
            }
        }
    }

    // MARK: - Factoring

    private var factoringFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Factoring company")
            GlassField(label: "State lender license (opt.)",
                       placeholder: "Where required",
                       icon: "checkmark.shield",
                       text: $vm.stateLenderLicense, autocapitalization: .characters)
            HStack(spacing: Space.s3) {
                GlassField(label: "Years in business",
                           placeholder: "5",
                           icon: "calendar",
                           text: $vm.yearsInBusiness, keyboardType: .numberPad)
                GlassField(label: "EIN (optional)",
                           placeholder: "XX-XXXXXXX",
                           icon: "building.columns",
                           text: $vm.ein, autocapitalization: .characters)
            }
            HStack(spacing: Space.s3) {
                GlassField(label: "Advance rate %",
                           placeholder: "90",
                           icon: "percent",
                           text: $vm.advanceRate, keyboardType: .decimalPad)
                GlassField(label: "Fee rate %",
                           placeholder: "3.5",
                           icon: "percent",
                           text: $vm.factoringFeeRate, keyboardType: .decimalPad)
            }
        }
    }

    // MARK: - Terminal Manager fields

    private var terminalFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Terminal / facility".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
            GlassField(label: "Company name (optional)",
                       placeholder: "Owner / operator entity",
                       icon: "building.2",
                       text: $vm.companyName, autocapitalization: .words)
                .focused($focus, equals: .company)
            GlassField(label: "Facility name",
                       placeholder: "Port of Houston · Terminal 5",
                       icon: "building.columns",
                       text: $vm.facilityName, autocapitalization: .words)
                .focused($focus, equals: .facilityName)
            GlassField(label: "EPA facility ID (if hazmat)",
                       placeholder: "TX0000000000",
                       icon: "leaf",
                       text: $vm.epaFacilityId, autocapitalization: .characters)
                .focused($focus, equals: .epaFacilityId)
            GlassField(label: "Company invite code (optional)",
                       placeholder: "From parent carrier / shipper",
                       icon: "key.horizontal",
                       text: $vm.companyCode, autocapitalization: .characters)
                .focused($focus, equals: .companyCode)
        }
    }

    // MARK: - Compliance Officer fields

    private var complianceFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Compliance officer".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
            GlassField(label: "Company invite code",
                       placeholder: "Required · ties you to the carrier",
                       icon: "key.horizontal",
                       text: $vm.companyCode, autocapitalization: .characters)
                .focused($focus, equals: .companyCode)
            GlassField(label: "Certification number (optional)",
                       placeholder: "CDS / TSDCA / state cert",
                       icon: "checkmark.shield",
                       text: $vm.certificationNumber, autocapitalization: .characters)
                .focused($focus, equals: .certNumber)
            GlassField(label: "Training provider (optional)",
                       placeholder: "Smith System / FMCSA / state",
                       icon: "graduationcap",
                       text: $vm.trainingProvider, autocapitalization: .words)
                .focused($focus, equals: .trainingProvider)
            GlassField(label: "Training completed (optional)",
                       placeholder: "YYYY-MM-DD",
                       icon: "calendar",
                       text: $vm.trainingCompletionDate, keyboardType: .numbersAndPunctuation)
                .focused($focus, equals: .trainingCompletionDate)
        }
    }

    // MARK: - Safety Manager fields

    private var safetyFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Safety manager".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
            GlassField(label: "Company invite code",
                       placeholder: "Required · ties you to the carrier",
                       icon: "key.horizontal",
                       text: $vm.companyCode, autocapitalization: .characters)
                .focused($focus, equals: .companyCode)
            GlassField(label: "CSA specialist cert (optional)",
                       placeholder: "NSC / CSA cert #",
                       icon: "cross.case",
                       text: $vm.csaSpecialistCert, autocapitalization: .characters)
                .focused($focus, equals: .csaCert)
            GlassField(label: "Years of experience (optional)",
                       placeholder: "5",
                       icon: "number",
                       text: $vm.yearsOfExperience, keyboardType: .numberPad)
                .focused($focus, equals: .yearsExperience)
        }
    }

    // MARK: - Admin fields (invite-only)

    private var adminFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Platform admin".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
            GlassField(label: "Invite code",
                       placeholder: "Super-admin-issued token",
                       icon: "key",
                       text: $vm.inviteCode, autocapitalization: .characters)
                .focused($focus, equals: .inviteCode)
            // Gentle explainer so someone who lands here by mistake
            // knows the form is locked behind an invite rather than
            // hitting Submit and getting a server rejection later.
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Admin accounts can only be provisioned with a code from an existing super-admin. Without one, this form will not submit.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var driverFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("CDL & Driver details".uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)

            // Gemini Vision OCR — scan once, auto-fill the four fields
            // below (number, state, class, DOB) plus surface a warning
            // banner if the CDL is expired.
            CredentialScanCard(
                credentialType: cdlCredentialType,
                title: cdlScanTitle,
                subtitle: "We'll auto-fill number, state, class, DOB, and endorsements."
            ) { applyDriverCredential($0) }

            HStack(spacing: Space.s3) {
                GlassField(label: "CDL number", placeholder: "A1234567",
                           icon: "creditcard",
                           text: $vm.cdlNumber, autocapitalization: .characters)
                    .focused($focus, equals: .cdl)
                GlassField(label: "CDL state", placeholder: "TX", icon: nil,
                           text: $vm.cdlState, autocapitalization: .characters)
                    .focused($focus, equals: .cdlState)
            }
            classPicker
            GlassField(label: "Date of birth (optional)", placeholder: "YYYY-MM-DD",
                       icon: "calendar",
                       text: $vm.dateOfBirth, keyboardType: .numbersAndPunctuation)
                .focused($focus, equals: .dob)
            GlassField(label: "Company invite code (optional)",
                       placeholder: "Paste code from your dispatcher",
                       icon: "key.horizontal",
                       text: $vm.companyCode, autocapitalization: .characters)
                .focused($focus, equals: .companyCode)

            // Optional second scan — DOT physical medical card. Doesn't
            // map to a VM field today, but a successful scan still
            // hashes through documentManagement on submit so the
            // driver's compliance dashboard light goes green from day 1.
            CredentialScanCard(
                credentialType: "us_medical_card",
                title: "Scan DOT medical card (optional)",
                subtitle: "Required for hazmat / Class A. We'll track the exam expiration."
            ) { _ in }
        }
    }

    // MARK: — Driver credential scan helpers
    //
    // Country-aware: US drivers scan their CDL, Canadian drivers their
    // Class 1, Mexican drivers their Licencia Federal. The wizard
    // already gathered country selection on Step 1, so we pick the
    // credential type from `vm.selectedCountries` (first match — most
    // drivers register against one country).

    private var driverCountry: RegistrationCountry? {
        vm.selectedCountries.first
    }

    private var cdlCredentialType: String {
        switch driverCountry {
        case .ca: return "ca_class1_license"
        case .mx: return "mx_licencia_federal"
        default:  return "us_cdl"
        }
    }

    private var cdlScanTitle: String {
        switch driverCountry {
        case .ca: return "Scan your Class 1 license"
        case .mx: return "Escanea tu Licencia Federal"
        default:  return "Scan your CDL"
        }
    }

    private func applyDriverCredential(_ r: CredentialScannerAPI.ScannedCredential) {
        if let s = r.identifier?.value?.stringValue { vm.cdlNumber = s }
        if let s = r.issuingJurisdiction?.value?.stringValue { vm.cdlState = s }
        if let s = r.licenseClass?.value?.stringValue {
            // Strip the "Class " prefix Gemini sometimes includes.
            let stripped = s.replacingOccurrences(of: "Class ", with: "")
                .trimmingCharacters(in: .whitespaces)
            if ["A", "B", "C"].contains(stripped) { vm.cdlClass = stripped }
        }
        if let s = r.holderDOB?.value?.stringValue { vm.dateOfBirth = s }
    }

    private var classPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CDL CLASS").font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(["A", "B", "C"], id: \.self) { c in
                    Button { vm.cdlClass = c } label: {
                        Text("Class \(c)")
                            .font(EType.caption)
                            .padding(.horizontal, Space.s3)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(vm.cdlClass == c ? .white : palette.textPrimary)
                            .background(
                                Group {
                                    if vm.cdlClass == c {
                                        LinearGradient.diagonal
                                    } else {
                                        palette.bgCardSoft.opacity(0.85)
                                    }
                                }
                            )
                            .overlay(Capsule().strokeBorder(vm.cdlClass == c ? Color.clear : palette.borderSoft))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var carrierFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Carrier company")

            // Scan the FMCSA authority letter — auto-fills DOT + MC +
            // legal entity name + hazmat-authorized flag in one tap.
            CredentialScanCard(
                credentialType: "us_dot_authority",
                title: "Scan your USDOT / MC authority letter",
                subtitle: "Auto-fills DOT, MC, legal name, and hazmat authorization."
            ) { applyCarrierAuthority($0) }

            // FMCSA SAFER live verification — typing a DOT or MC and
            // tapping Verify pulls the authoritative SAFER record:
            // legal name, addresses, fleet size, authority status,
            // hazmat, insurance posture, safety rating, and warnings.
            // Parity with web `FMCSALookup`.
            FMCSALookupCard(
                mode: .both,
                dotNumber: $vm.dotNumber,
                mcNumber: $vm.mcNumber
            ) { applyFMCSALookup($0) }

            HStack(spacing: Space.s3) {
                GlassField(label: "MC number", placeholder: "MC-123456", icon: "number",
                           text: $vm.mcNumber, autocapitalization: .characters)
                    .focused($focus, equals: .mc)
                GlassField(label: "DOT number", placeholder: "1234567",
                           icon: nil, text: $vm.dotNumber, keyboardType: .numberPad)
                    .focused($focus, equals: .dot)
            }
            GlassField(label: "EIN (optional)", placeholder: "XX-XXXXXXX",
                       icon: "building.columns", text: $vm.ein)
                .focused($focus, equals: .ein)

            // Optional second scan — ACORD 25 COI. Pre-validates that
            // their auto liability meets DOT minimums before the
            // first load posts.
            CredentialScanCard(
                credentialType: "us_coi",
                title: "Scan your ACORD 25 COI (optional)",
                subtitle: "Pulls policy #, insurer, auto / cargo limits, MCS-90, and expiration."
            ) { applyCarrierCOI($0) }
        }
    }

    private var brokerFields: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            companyBlock(title: "Brokerage")

            // Scan broker authority letter — same OCR path as carrier
            // since the FMCSA confirmation letter shapes are similar.
            CredentialScanCard(
                credentialType: "us_mc_authority",
                title: "Scan your MC authority letter",
                subtitle: "Auto-fills MC number, legal entity, and operating status."
            ) { applyBrokerAuthority($0) }

            // FMCSA SAFER live verification. Brokers register with MC
            // primarily so the card defaults to .mc mode but the
            // user can switch fields if they only know their DOT.
            FMCSALookupCard(
                mode: .both,
                dotNumber: $vm.dotNumber,
                mcNumber: $vm.brokerMcNumber
            ) { applyFMCSALookup($0) }

            GlassField(label: "Broker MC #", placeholder: "MC-123456",
                       icon: "number",
                       text: $vm.brokerMcNumber, autocapitalization: .characters)
                .focused($focus, equals: .brokerMC)
            HStack(spacing: Space.s3) {
                GlassField(label: "Bond provider (opt.)",
                           placeholder: "Company name",
                           icon: "shield",
                           text: $vm.bondProvider, autocapitalization: .words)
                    .focused($focus, equals: .bondProv)
                GlassField(label: "Bond amount",
                           placeholder: "75000",
                           icon: "dollarsign",
                           text: $vm.bondAmount, keyboardType: .decimalPad)
                    .focused($focus, equals: .bondAmt)
            }

            // Optional bond scan — BMC-84 surety bond confirmation.
            // Sets bondProvider + bondAmount in one tap.
            CredentialScanCard(
                credentialType: "bond_bmc84",
                title: "Scan your BMC-84 surety bond (optional)",
                subtitle: "Auto-fills surety company, bond number, and bond amount."
            ) { applyBrokerBond($0) }
        }
    }

    // MARK: — Carrier / broker scan appliers

    private func applyCarrierAuthority(_ r: CredentialScannerAPI.ScannedCredential) {
        if let s = r.usdotNumber?.value?.stringValue { vm.dotNumber = s }
        if let s = r.mcNumber?.value?.stringValue { vm.mcNumber = s }
        if let s = r.legalEntityName?.value?.stringValue, vm.companyName.isEmpty {
            vm.companyName = s
        }
    }

    private func applyCarrierCOI(_ r: CredentialScannerAPI.ScannedCredential) {
        // No COI-specific VM fields today — values are captured for
        // post-signup compliance dashboard via documentManagement on
        // submit. The card still surfaces the scan envelope so the
        // user sees expiration + limits before continuing.
        _ = r
    }

    private func applyBrokerAuthority(_ r: CredentialScannerAPI.ScannedCredential) {
        if let s = r.mcNumber?.value?.stringValue { vm.brokerMcNumber = s }
        if let s = r.legalEntityName?.value?.stringValue, vm.companyName.isEmpty {
            vm.companyName = s
        }
    }

    private func applyBrokerBond(_ r: CredentialScannerAPI.ScannedCredential) {
        if let s = r.additional?["suretyName"] { vm.bondProvider = s }
        if let s = r.additional?["bondAmount"] { vm.bondAmount = s }
    }

    /// Apply a FMCSA SAFER verified envelope to the registration
    /// view-model. The card already updates `dotNumber` / `mcNumber`
    /// in place (they're bindings on the input row); this fills the
    /// rest: companyName, ein placeholder, address, city, state, zip.
    /// Brokers' `brokerMcNumber` is also kept in sync.
    private func applyFMCSALookup(_ l: FMCSACarrierLookup) {
        guard l.verified, l.isBlocked != true else { return }
        if let p = l.companyProfile {
            if vm.companyName.isEmpty { vm.companyName = p.legalName }
            // Physical address takes priority — many carriers' mailing
            // address is a PO box that won't satisfy compliance.
            let addr = p.physicalAddress
            if vm.address.isEmpty { vm.address = addr.street }
            if vm.city.isEmpty { vm.city = addr.city }
            if vm.state.isEmpty { vm.state = addr.state }
            if vm.zip.isEmpty { vm.zip = addr.zip }
        }
        if let a = l.authority {
            // Echo the canonical DOT back so the form matches SAFER's
            // spelling (zero-padding, etc.).
            if !a.dotNumber.isEmpty { vm.dotNumber = a.dotNumber }
        }
    }

    // MARK: — Rail / vessel / customs scan appliers

    private func applyFRACert(_ r: CredentialScannerAPI.ScannedCredential) {
        if let s = r.identifier?.value?.stringValue { vm.fraCertificationNumber = s }
        if let s = r.expirationDate?.value?.stringValue { vm.fraCertificationExpires = s }
        if let s = r.issuingAuthority?.value?.stringValue, vm.employerRailroad.isEmpty {
            vm.employerRailroad = s
        }
        if let s = r.holderDOB?.value?.stringValue { vm.dateOfBirth = s }
    }

    private func applyVesselDoc(_ r: CredentialScannerAPI.ScannedCredential) {
        if let s = r.identifier?.value?.stringValue { vm.uscgDocumentNumber = s }
        if let s = r.legalEntityName?.value?.stringValue, vm.companyName.isEmpty {
            vm.companyName = s
        }
    }

    private func applyMMC(_ r: CredentialScannerAPI.ScannedCredential) {
        if let s = r.identifier?.value?.stringValue { vm.mmcLicenseNumber = s }
        if let s = r.expirationDate?.value?.stringValue { vm.mmcExpires = s }
        if let s = r.holderDOB?.value?.stringValue { vm.dateOfBirth = s }
    }

    private func applyCBPLicense(_ r: CredentialScannerAPI.ScannedCredential) {
        if let s = r.identifier?.value?.stringValue { vm.cbpLicenseNumber = s }
        if let s = r.expirationDate?.value?.stringValue { vm.cbpLicenseExpires = s }
    }

    @ViewBuilder
    private func companyBlock(title: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
            GlassField(label: "Company name", placeholder: "Acme Freight Co.",
                       icon: "building.2",
                       text: $vm.companyName, autocapitalization: .words)
                .focused($focus, equals: .company)
        }
    }

    private func addressBlock() -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Single smart address picker — HERE autosuggest + lat/lng
            // paste detection. Mirrors its `.text` onto `vm.address` so
            // the backend payload is unchanged; coords are carried on
            // `vm.companyResolvedAddress` for downstream use.
            EusoAddressField(
                label: "Address",
                placeholder: "123 Main St or 40.7128, -74.0060",
                value: $vm.companyResolvedAddress
            )
            .onChange(of: vm.companyResolvedAddress) { _, new in
                vm.address = new.text
            }
            HStack(spacing: Space.s3) {
                GlassField(label: "City", placeholder: "Houston", icon: nil,
                           text: $vm.city, autocapitalization: .words)
                    .focused($focus, equals: .city)
                GlassField(label: "State", placeholder: "TX", icon: nil,
                           text: $vm.state, autocapitalization: .characters)
                    .focused($focus, equals: .state)
                GlassField(label: "ZIP", placeholder: "77001", icon: nil,
                           text: $vm.zip, keyboardType: .numberPad)
                    .focused($focus, equals: .zip)
            }
        }
    }

    // MARK: Step 5 — Verify email

    private var verifyEmailCard: some View {
        GlassCard {
            VStack(spacing: Space.s4) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal.opacity(0.15))
                        .frame(width: 96, height: 96)
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(LinearGradient.diagonal)
                        .symbolEffect(.bounce, value: true)
                }
                Text("Check your email")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                Text("We sent a verification link to \(vm.email.isEmpty ? "your inbox" : vm.email). Tap it to activate your account.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)

                // Carrier roles get an additional "While you wait…"
                // shortcut to fleet + driver setup. Submitting these
                // before email verification is fine — the server
                // accepts the calls under the freshly-issued bearer
                // and the rows file under the new company immediately.
                if showsCarrierKickstart {
                    carrierKickstart
                }

                CTAButton(title: "Back to sign in") { dismiss() }
                Button("Resend email") {
                    Task { _ = try? await EusoTripAPI.shared.registration.resendVerification(email: vm.email) }
                }
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            }
        }
        .sheet(isPresented: $showFleetSetup) {
            FleetBulkRegisterStep(
                vertical: kickstartVertical,
                onContinue: { showFleetSetup = false },
                onSkip: { showFleetSetup = false }
            )
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $showInviteTeam) {
            DriverInviteBulkStep(
                vertical: kickstartVertical,
                onContinue: { showInviteTeam = false },
                onSkip: { showInviteTeam = false }
            )
            .environment(\.palette, palette)
        }
    }

    /// Show the "While you wait" carrier kickstart row for company-
    /// owning roles. Solo drivers / shippers / staff don't need it.
    private var showsCarrierKickstart: Bool {
        switch vm.role {
        case .catalyst, .broker, .railCatalyst, .railBroker, .vesselOperator, .vesselBroker:
            return true
        default:
            return false
        }
    }

    private var kickstartVertical: String {
        switch vm.role {
        case .railCatalyst, .railBroker: return "rail"
        case .vesselOperator, .vesselBroker: return "vessel"
        default: return "truck"
        }
    }

    private var carrierKickstart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHILE YOU WAIT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                Button { showFleetSetup = true } label: {
                    kickstartTile(icon: "truck.box.fill",
                                  title: "Add your fleet",
                                  subtitle: "Scan VINs · seed maintenance + DVIR")
                }
                .buttonStyle(.plain)
                Button { showInviteTeam = true } label: {
                    kickstartTile(icon: "person.2.fill",
                                  title: "Invite your team",
                                  subtitle: "One email per teammate · deep-link signup")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func kickstartTile(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft.opacity(0.65))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.35))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Shared chrome

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(palette.bgCard.opacity(0.85))
                        .overlay(Circle().strokeBorder(palette.borderSoft))
                        .clipShape(Circle())
                }
                .padding(Space.s4)
            }
            Spacer()
        }
    }

    private var helperFooter: some View {
        VStack(spacing: 6) {
            Text("Need help choosing? Contact support@eusotrip.com")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 4) {
                Text("By registering, you agree to our")
                    .foregroundStyle(palette.textTertiary)
                Button("Terms") { showTerms = true }
                    .foregroundStyle(LinearGradient.diagonal)
                Text("and")
                    .foregroundStyle(palette.textTertiary)
                Button("Privacy Policy") { showPrivacy = true }
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .font(EType.caption)
        }
        .multilineTextAlignment(.center)
        .padding(.top, Space.s3)
    }

    // MARK: Buttons & chips

    private func primaryCTA(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(EType.bodyStrong)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(LinearGradient.diagonal)
            .clipShape(Capsule())
            .shadow(color: Brand.blue.opacity(enabled ? 0.32 : 0),
                    radius: 18, x: -4, y: 10)
            .shadow(color: Brand.magenta.opacity(enabled ? 0.28 : 0),
                    radius: 22, x: 4, y: 14)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
        .sensoryFeedback(.selection, trigger: step)
    }

    private func secondaryButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(EType.bodyStrong)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Space.s4)
            .frame(height: 50)
            .background(palette.bgCardSoft.opacity(0.75))
            .overlay(Capsule().strokeBorder(palette.borderSoft))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func checkmarkPill(selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.7))
                                       : AnyShapeStyle(palette.borderSoft),
                              lineWidth: selected ? 1.6 : 1)
                .frame(width: 24, height: 24)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    private func tagPill(text: String, color: Color, subtle: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(subtle ? color : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(subtle ? 0.08 : 0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(0.35), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // Brand-accent pill — satisfies doctrine §2.1 (gradient, not blue).
    // Use this for any recap/badge tag that would otherwise be Brand.blue / Brand.info.
    private func gradientTagPill(text: String, subtle: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(LinearGradient.diagonal)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                LinearGradient.diagonal.opacity(subtle ? 0.08 : 0.15)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var isSubmitting: Bool {
        if case .submitting = vm.phase { return true }
        return false
    }

    private var isSuccess: Bool {
        if case .success = vm.phase { return true }
        return false
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.danger)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.12))
        .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - FlowLayout

/// Simple wrap/flow layout — used for tag pills and requirement chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width {
                y += rowHeight + spacing
                maxWidth = max(maxWidth, x - spacing)
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        maxWidth = max(maxWidth, x - spacing)
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

// MARK: - Previews (Dark + Light)

#Preview("Create Account · Dark") {
    CreateAccountView()
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Create Account · Light") {
    CreateAccountView()
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
