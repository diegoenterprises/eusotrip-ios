//
//  001_SignIn.swift
//  EusoTrip — Sign-in screen (glass auth surface).
//
//  Parity with web platform /login page:
//    • Email + password
//    • 2FA gate (TOTP 6-digit OR SMS fallback)
//    • Forgot password link
//    • Create account link
//    • Privacy Policy / Terms footer
//
//  Aesthetic: AuroraBackground + GradientLogo + GlassCard + GlassField.
//  Both Dark and Light palette previews ship below.
//

import SwiftUI

struct SignInView: View {
    @Environment(\.palette) var palette
    @EnvironmentObject var session: EusoTripSession
    @StateObject private var vm = LoginViewModel()
    @FocusState private var focus: Field?

    enum Field: Hashable { case email, password, twofa }

    @State private var showForgotPassword = false
    @State private var showCreateAccount = false
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        ZStack {
            AuroraBackground()
                // Tap any non-interactive backdrop area to drop focus.
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }
            ScrollView {
                // TileStack — logo/header tile → credentials glass card →
                // footer links, each fading and lifting into place in
                // order, matching the web platform's login entrance.
                TileStack(spacing: Space.s6) {
                    header
                    GlassCard {
                        switch vm.phase {
                        case .twoFactor(let method):
                            twoFactorForm(method: method)
                        default:
                            credentialsForm
                        }
                    }
                    footer
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s6)
                .padding(.bottom, Space.s5)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            // Drag/flick down over the scroll view dismisses the keyboard.
            .scrollDismissesKeyboard(.interactively)
        }
        // Global Done button above every keyboard in this screen.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.phase)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
                .environmentObject(session)
                .eusoSheet()
        }
        .sheet(isPresented: $showCreateAccount) {
            CreateAccountView()
                .environmentObject(session)
                .eusoSheet()
        }
        .sheet(isPresented: $showTerms) {
            TermsOfServiceView().eusoSheet()
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyPolicyView().eusoSheet()
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Space.s4) {
            GradientLogo(size: 96)
            VStack(spacing: 4) {
                Text("Welcome back")
                    .font(EType.h1)
                    .foregroundStyle(palette.textPrimary)
                Text("Sign in to EusoTrip")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            IridescentHairline().padding(.top, Space.s2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Credentials form

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassField(
                label: "Email",
                placeholder: "you@company.com",
                icon: "envelope",
                text: $vm.email,
                keyboardType: .emailAddress,
                textContentType: .emailAddress,
                error: vm.emailError
            )
            .focused($focus, equals: .email)

            GlassField(
                label: "Password",
                placeholder: "••••••••",
                icon: "lock",
                text: $vm.password,
                isSecure: true,
                textContentType: .password,
                error: vm.passwordError
            )
            .focused($focus, equals: .password)

            HStack {
                Spacer()
                Button("Forgot password?") { showForgotPassword = true }
                    .font(EType.caption)
                    .foregroundStyle(LinearGradient.diagonal)
            }

            if case .error(let msg) = vm.phase { errorBanner(msg) }

            CTAButton(
                title: phaseIsSubmitting ? "Signing in…" : "Sign in",
                action: { Task { await vm.submit(session: session) } }
            )
            .opacity(vm.canSubmit && !phaseIsSubmitting ? 1 : 0.55)
            .disabled(!vm.canSubmit || phaseIsSubmitting)

            orDivider

            Button {
                showCreateAccount = true
            } label: {
                HStack(spacing: 6) {
                    Text("New to EusoTrip?")
                        .foregroundStyle(palette.textSecondary)
                    Text("Create account")
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .font(EType.caption)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(palette.bgCardSoft.opacity(0.7))
                .overlay(Capsule().strokeBorder(palette.borderSoft))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Offline/demo entry — wires the full production flow
            // (SignIn → ContentView → DriverTripController) without a
            // live backend so the Figma-faithful walkthrough is
            // demonstrable end-to-end in the simulator / TestFlight.
            demoEntryRow
        }
    }

    // MARK: Demo entry row

    private var demoEntryRow: some View {
        VStack(spacing: Space.s2) {
            Text("Preview without backend")
                .font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                demoChip(title: "Driver",  role: .driver)
                demoChip(title: "Shipper", role: .shipper)
                demoChip(title: "Broker",  role: .broker)
            }
        }
        .padding(.top, Space.s2)
    }

    private func demoChip(title: String, role: EusoRole) -> some View {
        Button {
            focus = nil
            session.signInDemo(role: role)
        } label: {
            Text(title)
                .font(EType.caption)
                .foregroundStyle(LinearGradient.diagonal)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(palette.bgCardSoft.opacity(0.55))
                .overlay(Capsule().strokeBorder(palette.borderSoft))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 2FA form

    private func twoFactorForm(method: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s2) {
                Image(systemName: method == "sms" ? "iphone" : "shield.lefthalf.filled")
                    .foregroundStyle(LinearGradient.diagonal)
                Text(method == "sms" ? "SMS verification" : "Two-factor authentication")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }

            Text(method == "sms"
                 ? "Enter the 6-digit code we just texted you."
                 : "Enter the 6-digit code from your authenticator app.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)

            GlassField(
                label: "6-digit code",
                placeholder: "123 456",
                icon: "number.square",
                text: $vm.twoFactorCode,
                keyboardType: .numberPad,
                textContentType: .oneTimeCode
            )
            .focused($focus, equals: .twofa)

            if case .error(let msg) = vm.phase { errorBanner(msg) }

            CTAButton(
                title: phaseIsSubmitting ? "Verifying…" : "Verify & sign in",
                action: { Task { await vm.submitTwoFactor(session: session) } }
            )
            .opacity(vm.canSubmitTOTP && !phaseIsSubmitting ? 1 : 0.55)
            .disabled(!vm.canSubmitTOTP || phaseIsSubmitting)

            Button("Use a different account") {
                vm.phase = .idle
                vm.twoFactorCode = ""
            }
            .font(EType.caption)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.s2)
        }
    }

    private var phaseIsSubmitting: Bool {
        if case .submitting = vm.phase { return true }
        return false
    }

    // MARK: Shared chrome

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

    private var orDivider: some View {
        HStack(spacing: Space.s3) {
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            Text("OR").font(EType.micro).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button("Terms of Service") { showTerms = true }
                    .foregroundStyle(palette.textSecondary)
                Text("·").foregroundStyle(palette.textTertiary)
                Button("Privacy Policy") { showPrivacy = true }
                    .foregroundStyle(palette.textSecondary)
            }
            .font(EType.caption)
            Text("© Eusorone Technologies, Inc.")
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, Space.s2)
    }
}

// MARK: - Previews (Dark + Light)

#Preview("Sign In · Dark") {
    SignInView()
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Sign In · Light") {
    SignInView()
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
