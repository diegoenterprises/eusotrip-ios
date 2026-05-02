//
//  369_BackgroundBiometric.swift
//  EusoTrip — Shipper · Background biometric re-prompt (Arc M).
//

import SwiftUI
import LocalAuthentication

struct BackgroundBiometricScreen: View {
    let theme: Theme.Palette
    var onUnlock: () -> Void = {}
    var body: some View {
        Shell(theme: theme) { BiometricBody(onUnlock: onUnlock) } nav: { shipperLifecycleNav() }
    }
}

private struct BiometricBody: View {
    @Environment(\.palette) private var palette
    let onUnlock: () -> Void
    @State private var prompting = false
    @State private var actionError: String? = nil

    private var biometryLabel: String {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return "Passcode" }
        switch ctx.biometryType {
        case .none:      return "Passcode"
        case .faceID:    return "Face ID"
        case .touchID:   return "Touch ID"
        case .opticID:   return "Optic ID"
        @unknown default: return "Passcode"
        }
    }

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            Image(systemName: biometryLabel == "Face ID" ? "faceid" : (biometryLabel == "Touch ID" ? "touchid" : "lock.fill"))
                .font(.system(size: 56, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("Welcome back").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Authenticate with \(biometryLabel) to unlock the app.")
                .font(EType.body).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            if let err = actionError { Text(err).font(EType.caption).foregroundStyle(Brand.danger).padding(.horizontal, 32).multilineTextAlignment(.center) }
            Spacer()
            Button { Task { await authenticate() } } label: {
                HStack(spacing: 6) {
                    if prompting { ProgressView().tint(.white) }
                    Text(prompting ? "Authenticating…" : "Unlock with \(biometryLabel)").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(prompting)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Task { await authenticate() } }
    }

    private func authenticate() async {
        prompting = true; actionError = nil
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use passcode"
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock EusoTrip")
            if ok { onUnlock() }
        } catch {
            actionError = error.localizedDescription
        }
        prompting = false
    }
}

#Preview("369 · Biometric · Night") { BackgroundBiometricScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("369 · Biometric · Afternoon") { BackgroundBiometricScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
