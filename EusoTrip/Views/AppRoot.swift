//
//  AppRoot.swift
//  EusoTrip — Top-level router.
//
//  Decides between:
//    • booting   → splash with animated orb
//    • signedOut → SignInView (aurora + glass)
//    • signedIn  → ContentView (production screen walker)
//
//  Handles reset-password deep link by presenting ResetPasswordView over the
//  auth surface with the token prefilled.
//

import SwiftUI

struct AppRoot: View {
    @EnvironmentObject var session: EusoTripSession
    @State private var resetToken: String?
    @State private var showReset: Bool = false

    var body: some View {
        Group {
            switch session.phase {
            case .booting:
                BootSplash()
                    .screenTileRoot()
                    .id("root-booting")
                    .transition(.opacity)
            case .signedOut:
                // Production auth entry — real SignInView in every build.
                // For offline / simulator walkthroughs, SignInView exposes a
                // "Preview without backend" row that calls session.signInDemo
                // and routes through the same signedIn → ContentView →
                // DriverTripController pipeline, so the full production flow
                // is exercised end-to-end. (Previously this was a compile-
                // time #if DEBUG bypass that rendered ContentView directly.)
                //
                // PHASE 1 AUDIT (2026-04-23, eusotrip-killers §6 pass):
                // DEV_BYPASS_STATUS: REMOVED. Verified — no `#if DEBUG`
                // short-circuit remains. Auth flow is live on every build.
                // Deep-link reset password handler is wired at EusoTripApp
                // `.onOpenURL` → `NotificationCenter.eusoResetPasswordDeepLink`
                // → presented as a sheet from `AppRoot` below.
                SignInView()
                    .screenTileRoot()
                    .id("root-signedOut")
                    .transition(.opacity)
            case .signedIn:
                ContentView()
                    .screenTileRoot()
                    .id("root-signedIn")
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: session.phase)
        .onReceive(NotificationCenter.default.publisher(for: .eusoResetPasswordDeepLink)) { note in
            if let token = note.userInfo?["token"] as? String {
                resetToken = token
                showReset = true
            }
        }
        .sheet(isPresented: $showReset) {
            ResetPasswordView(presetToken: resetToken)
        }
    }
}

// MARK: - Boot splash

private struct BootSplash: View {
    @Environment(\.palette) var palette
    @State private var pulse = false

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: Space.s4) {
                OrbESang(state: .idle, diameter: 88)
                    .scaleEffect(pulse ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                               value: pulse)
                VStack(spacing: 4) {
                    Text("EusoTrip")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("by Eusorone Technologies · ESANG AI™".uppercased())
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Previews

#Preview("AppRoot · Dark") {
    AppRoot()
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("AppRoot · Light") {
    AppRoot()
        .environmentObject(EusoTripSession())
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
