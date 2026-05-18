//
//  AppleAuthButtons.swift
//  EusoTrip — Sign in with Apple + Passkey button row.
//
//  Drop-in `AppleAuthButtons()` view that renders the Apple-
//  branded "Sign in with Apple" button (system-provided so it
//  satisfies Apple's HIG for the capability) and a custom
//  "Sign in with passkey" button on the same row. Both drive
//  `EusoTripSession` directly so the host screen just observes
//  `session.phase` and the standard ContentView routing
//  switches to the authed shell on success.
//

import SwiftUI
import AuthenticationServices

public struct AppleAuthButtons: View {
    /// Optional email to constrain the passkey assertion to a
    /// specific account. Pass the SignIn screen's email field
    /// when known; the Create-Account screen leaves it nil.
    public let prefilledEmail: String?
    /// Layout — vertical on the SignIn screen, horizontal on
    /// compact contexts like sheets.
    public var axis: Axis = .vertical
    /// Whether to render the "Sign in with passkey" button. Disabled
    /// on the Create-Account screen since a new user can't have a
    /// passkey on file yet.
    public var showsPasskey: Bool = true

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: EusoTripSession
    @State private var error: String? = nil
    @State private var inflightApple = false
    @State private var inflightPasskey = false

    public init(prefilledEmail: String? = nil,
                axis: Axis = .vertical,
                showsPasskey: Bool = true) {
        self.prefilledEmail = prefilledEmail
        self.axis = axis
        self.showsPasskey = showsPasskey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if axis == .vertical {
                appleButton
                if showsPasskey { passkeyButton }
            } else {
                HStack(spacing: 8) {
                    appleButton
                    if showsPasskey { passkeyButton }
                }
            }
            if let e = error {
                Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: — Buttons

    private var appleButton: some View {
        // Use Apple's own SwiftUI button — it gives us the licensed
        // logo + label rendering + accessibility wiring for free
        // and is the only path that complies with Apple's HIG for
        // the Sign in with Apple capability.
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
            // The full nonce + token-hash dance lives inside
            // AppleAuthProvider.signInWithApple(); the system button
            // path here is the fallback for surfaces that don't
            // need PKCE nonce binding. Both routes converge on
            // auth.appleSignIn which verifies the JWT.
        } onCompletion: { _ in
            // The system button completes BEFORE our session call
            // because we run through AppleAuthProvider for the
            // full nonce-bound flow. The handler below kicks that
            // route on tap.
        }
        .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
        .frame(height: 50)
        .allowsHitTesting(!inflightApple)
        .overlay(
            // Transparent button on top to intercept the tap so we
            // can route through our async AppleAuthProvider flow
            // (which carries the nonce + ASAuthorizationController
            // back to AppleAuthProvider's continuation pipeline).
            Button(action: { Task { await runAppleSignIn() } }) {
                Color.clear
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sign in with Apple")
        )
        .overlay(alignment: .trailing) {
            if inflightApple { ProgressView().tint(.white).padding(.trailing, 12) }
        }
    }

    private var passkeyButton: some View {
        Button { Task { await runPasskeySignIn() } } label: {
            HStack(spacing: 8) {
                if inflightPasskey {
                    ProgressView().scaleEffect(0.7).tint(palette.textPrimary)
                } else {
                    Image(systemName: "faceid")
                        .font(.system(size: 17, weight: .heavy))
                }
                Text("Sign in with passkey")
                    .font(.system(size: 15, weight: .heavy))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(palette.textPrimary)
            .background(palette.bgCardSoft)
            .overlay(Capsule().strokeBorder(palette.borderSoft))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(inflightPasskey)
        .opacity(inflightPasskey ? 0.65 : 1.0)
    }

    // MARK: — Async runners

    @MainActor
    private func runAppleSignIn() async {
        guard !inflightApple else { return }
        inflightApple = true
        defer { inflightApple = false }
        error = nil
        do {
            let resp = try await session.signInWithApple()
            if !resp.success {
                // 2FA gates etc. surface inline. For first-launch we
                // never hit them on the Apple Sign-In path.
                error = resp.message ?? "Couldn't sign in with Apple."
            }
        } catch let e as EusoAuthError where e == .userCanceled {
            // No-op — user dismissed the system sheet.
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func runPasskeySignIn() async {
        guard !inflightPasskey else { return }
        inflightPasskey = true
        defer { inflightPasskey = false }
        error = nil
        do {
            let resp = try await session.signInWithPasskey(
                email: (prefilledEmail?.isEmpty == false) ? prefilledEmail : nil
            )
            if !resp.success {
                error = resp.message ?? "Couldn't sign in with passkey."
            }
        } catch let e as EusoAuthError where e == .userCanceled {
            // silent
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - EusoAuthError equality helper for the canceled fast-path

extension EusoAuthError: Equatable {
    public static func == (lhs: EusoAuthError, rhs: EusoAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.malformedAppleCredential, .malformedAppleCredential),
             (.malformedPasskeyOptions, .malformedPasskeyOptions),
             (.unexpectedPasskeyResponse, .unexpectedPasskeyResponse),
             (.authorizationInProgress, .authorizationInProgress),
             (.userCanceled, .userCanceled):
            return true
        case (.underlying(let a), .underlying(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Previews

#Preview("Apple Auth Buttons · Dark") {
    AppleAuthButtons(prefilledEmail: "diego@eusotrip.com")
        .padding(16)
        .environment(\.palette, Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("Apple Auth Buttons · Light") {
    AppleAuthButtons(showsPasskey: false)
        .padding(16)
        .environment(\.palette, Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
