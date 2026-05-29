//
//  003_ForgotPassword.swift
//  EusoTrip — Forgot password flow.
//
//  Backend: auth.forgotPassword(email)
//  Always returns success to prevent email enumeration.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var vm = ForgotPasswordViewModel()
    @FocusState private var focused: Bool
    @State private var showReset = false
    // Drives the success-checkmark settle: flips true once the real
    // `.sent` phase lands, so the bounce + spring scale-in are bound to
    // actual backend success rather than a hardcoded value.
    @State private var sentLanded = false

    var body: some View {
        ZStack {
            AuroraBackground()
                .contentShape(Rectangle())
                .onTapGesture { focused = false }
            ScrollView {
                // TileStack — staggered entrance for header → glass card
                // → reset-token link.
                TileStack(spacing: Space.s6) {
                    header
                    GlassCard {
                        switch vm.phase {
                        case .sent: sentCard
                        default:    form
                        }
                    }
                    Button("I have a reset token") {
                        showReset = true
                    }
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s6)
                .padding(.bottom, Space.s5)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            closeButton
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.phase)
        .sheet(isPresented: $showReset) { ResetPasswordView() }
        .onAppear { focused = true }
    }

    private var header: some View {
        VStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "key.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(spacing: 4) {
                Text("Forgot password?")
                    .font(EType.h1)
                    .foregroundStyle(palette.textPrimary)
                Text("We'll email you a secure reset link.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            IridescentHairline().padding(.top, Space.s2)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassField(label: "Email", placeholder: "you@company.com", icon: "envelope",
                       text: $vm.email,
                       keyboardType: .emailAddress,
                       textContentType: .emailAddress)
                .focused($focused)

            if case .error(let msg) = vm.phase { errorBanner(msg) }

            CTAButton(
                title: isSubmitting ? "Sending…" : "Send reset link",
                action: { Task { await vm.submit() } }
            )
            .opacity(vm.canSubmit && !isSubmitting ? 1 : 0.55)
            .disabled(!vm.canSubmit || isSubmitting)
        }
    }

    private var sentCard: some View {
        VStack(spacing: Space.s4) {
            ZStack {
                Circle()
                    .fill(Brand.success.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Brand.success)
                    // Bounce is bound to the *real* landed-success flag,
                    // not a constant, so it only fires when the backend
                    // returns .sent. Suppressed entirely under reduce-motion.
                    .symbolEffect(.bounce, value: reduceMotion ? false : sentLanded)
            }
            // Spring settle: the success glyph scales up from 0.6→1 with a
            // gentle overshoot the moment .sent lands. Reduce-motion shows the
            // final state (scale 1, full opacity) with no motion.
            .scaleEffect(reduceMotion || sentLanded ? 1 : 0.6)
            .opacity(reduceMotion || sentLanded ? 1 : 0)
            .animation(
                reduceMotion ? nil
                             : .spring(response: 0.5, dampingFraction: 0.62),
                value: sentLanded
            )
            Text("Check your inbox")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Text("If an account exists for \(vm.email), we've sent a password reset link. The link expires in 1 hour.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            CTAButton(title: "Back to sign in") { dismiss() }
        }
        .sensoryFeedback(.success, trigger: vm.phase)
        // The card only renders when phase == .sent, so onAppear here is the
        // exact moment real success lands — wire the settle/bounce trigger to it.
        .onAppear {
            if reduceMotion { sentLanded = true }
            else { DispatchQueue.main.async { sentLanded = true } }
        }
        .onDisappear { sentLanded = false }
    }

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

    private var isSubmitting: Bool {
        if case .submitting = vm.phase { return true }
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

// MARK: - Previews (Dark + Light)

#Preview("Forgot Password · Dark") {
    ForgotPasswordView()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Forgot Password · Light") {
    ForgotPasswordView()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
