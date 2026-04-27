//
//  004_ResetPassword.swift
//  EusoTrip — Complete reset after receiving email token.
//
//  Backend: auth.resetPassword({ token, newPassword: min(8) })
//

import SwiftUI

struct ResetPasswordView: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = ResetPasswordViewModel()
    @FocusState private var focus: Field?

    enum Field { case token, password, confirm }

    /// Optional pre-filled token from deep link (`eusotrip://reset?token=…`).
    var presetToken: String? = nil

    var body: some View {
        ZStack {
            AuroraBackground()
                .contentShape(Rectangle())
                .onTapGesture { focus = nil }
            ScrollView {
                // TileStack — staggered entrance for header → glass card.
                TileStack(spacing: Space.s6) {
                    header
                    GlassCard {
                        if case .done = vm.phase { doneCard } else { form }
                    }
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
                Button("Done") { focus = nil }
                    .foregroundStyle(LinearGradient.diagonal)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.phase)
        .onAppear {
            if let t = presetToken { vm.token = t }
            focus = presetToken == nil ? .token : .password
        }
    }

    private var header: some View {
        VStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "lock.rotation")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(spacing: 4) {
                Text("Reset your password")
                    .font(EType.h1)
                    .foregroundStyle(palette.textPrimary)
                Text("Choose a new password — 8 characters minimum.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            IridescentHairline().padding(.top, Space.s2)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            GlassField(label: "Reset token",
                       placeholder: "Paste from email",
                       icon: "key.horizontal",
                       text: $vm.token,
                       autocapitalization: .never)
                .focused($focus, equals: .token)

            GlassField(label: "New password",
                       placeholder: "Minimum 8 characters",
                       icon: "lock",
                       text: $vm.newPassword,
                       isSecure: true,
                       textContentType: .newPassword)
                .focused($focus, equals: .password)

            GlassField(label: "Confirm password",
                       placeholder: "Repeat password",
                       icon: "lock.fill",
                       text: $vm.confirmPassword,
                       isSecure: true,
                       textContentType: .newPassword)
                .focused($focus, equals: .confirm)

            passwordStrengthMeter

            if case .error(let msg) = vm.phase { errorBanner(msg) }

            CTAButton(
                title: isSubmitting ? "Updating…" : "Update password",
                action: { Task { await vm.submit() } }
            )
            .opacity(vm.canSubmit && !isSubmitting ? 1 : 0.55)
            .disabled(!vm.canSubmit || isSubmitting)
        }
    }

    private var doneCard: some View {
        VStack(spacing: Space.s4) {
            ZStack {
                Circle()
                    .fill(Brand.success.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Brand.success)
                    .symbolEffect(.bounce, value: true)
            }
            Text("Password updated")
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            Text("You can now sign in with your new password.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            CTAButton(title: "Back to sign in") { dismiss() }
        }
        .sensoryFeedback(.success, trigger: vm.phase)
    }

    private var passwordStrengthMeter: some View {
        let score = strength(of: vm.newPassword)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < score
                              ? AnyShapeStyle(LinearGradient.diagonal)
                              : AnyShapeStyle(palette.borderFaint))
                        .frame(height: 4)
                }
            }
            Text(strengthLabel(score))
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func strength(of s: String) -> Int {
        var n = 0
        if s.count >= 8 { n += 1 }
        if s.contains(where: \.isNumber) { n += 1 }
        if s.contains(where: { $0.isLetter && $0.isUppercase }) { n += 1 }
        if s.contains(where: { "!@#$%^&*()_-+={}[]|:;\"'<>,.?/".contains($0) }) { n += 1 }
        return n
    }

    private func strengthLabel(_ n: Int) -> String {
        switch n {
        case 0: return "ENTER A PASSWORD"
        case 1: return "WEAK"
        case 2: return "FAIR"
        case 3: return "GOOD"
        default: return "STRONG"
        }
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

#Preview("Reset · Dark") {
    ResetPasswordView()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Reset · Light") {
    ResetPasswordView()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
