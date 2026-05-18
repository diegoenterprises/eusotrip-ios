//
//  AppleAuthProvider.swift
//  EusoTrip — Sign in with Apple + Passkeys (WebAuthn)
//
//  Single `ASAuthorizationController` host that handles three
//  related flows:
//
//    1. Sign in with Apple
//         `ASAuthorizationAppleIDProvider().createRequest()`
//         The user completes Face-ID / passcode, Apple hands us an
//         `identityToken` JWT we ship to the server which verifies
//         it against `https://appleid.apple.com/auth/keys`.
//
//    2. Passkey registration (post-sign-in)
//         `ASAuthorizationPlatformPublicKeyCredentialProvider`
//                 .createCredentialRegistrationRequest(...)
//         Returns an `attestationObject` + `clientDataJSON` we
//         ship to `auth.passkeyRegisterFinish`.
//
//    3. Passkey assertion (sign-in via Face-ID)
//         `ASAuthorizationPlatformPublicKeyCredentialProvider`
//                 .createCredentialAssertionRequest(...)
//         Returns an ECDSA signature + authenticatorData we ship
//         to `auth.passkeyAuthFinish`.
//
//  All three live behind `async` continuation-based methods so
//  call sites stay flat (no delegate-trampoline boilerplate in
//  the SwiftUI host).
//

import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

@MainActor
final class AppleAuthProvider: NSObject {
    static let shared = AppleAuthProvider()

    /// Relying-Party ID for passkeys. MUST match
    /// `services/auth/passkey.ts → RP_ID` AND the entitlement
    /// `webcredentials:<rpId>`. Override via Info.plist
    /// `EUSO_PASSKEY_RP_ID` only for staging.
    var passkeyRpId: String {
        (Bundle.main.object(forInfoDictionaryKey: "EUSO_PASSKEY_RP_ID") as? String) ?? "eusotrip.com"
    }

    private var pendingContinuation: CheckedContinuation<ASAuthorization, Error>?
    private var presentationAnchor: ASPresentationAnchor?

    // MARK: — Sign in with Apple

    struct AppleSignInPayload {
        /// JWT we hand to `auth.appleSignIn`.
        let identityToken: String
        /// Single-use authorization code (server-to-server flow).
        let authorizationCode: String?
        let userIdentifier: String
        let givenName: String?
        let familyName: String?
        let email: String?
        /// The plain nonce we sent. Server verifies the hashed form
        /// embedded in the identity token.
        let nonce: String
    }

    /// Kick off Sign in with Apple and resolve with the verified
    /// payload. The caller is expected to ship `identityToken` +
    /// `authorizationCode` to `auth.appleSignIn` on the server.
    func signInWithApple() async throws -> AppleSignInPayload {
        let nonce = Self.makeNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let auth = try await perform(requests: [request])

        guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = cred.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw EusoAuthError.malformedAppleCredential
        }
        let codeString: String? = {
            guard let data = cred.authorizationCode else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        return AppleSignInPayload(
            identityToken: identityToken,
            authorizationCode: codeString,
            userIdentifier: cred.user,
            givenName: cred.fullName?.givenName,
            familyName: cred.fullName?.familyName,
            email: cred.email,
            nonce: nonce
        )
    }

    // MARK: — Passkey registration

    struct PasskeyRegistrationStartOptions {
        let challengeB64URL: String     // already base64url, server-issued
        let userHandleB64URL: String    // base64url
        let userName: String
        let userDisplayName: String
    }

    struct PasskeyRegistrationResult {
        let credentialId: String           // base64url
        let attestationObject: String      // base64url
        let clientDataJSON: String         // base64url
    }

    /// Register a new passkey for the signed-in user. The server's
    /// `passkeyRegisterStart` returns the options; this method
    /// presents the iOS sheet and returns the attestation envelope
    /// to ship to `passkeyRegisterFinish`.
    func registerPasskey(options: PasskeyRegistrationStartOptions) async throws -> PasskeyRegistrationResult {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: passkeyRpId)
        guard let challengeData = Self.base64URLDecode(options.challengeB64URL),
              let userIDData = Self.base64URLDecode(options.userHandleB64URL) else {
            throw EusoAuthError.malformedPasskeyOptions
        }
        let request = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: options.userDisplayName,
            userID: userIDData
        )
        let auth = try await perform(requests: [request])

        guard let cred = auth.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            throw EusoAuthError.unexpectedPasskeyResponse
        }
        return PasskeyRegistrationResult(
            credentialId: Self.base64URLEncode(cred.credentialID),
            attestationObject: Self.base64URLEncode(cred.rawAttestationObject ?? Data()),
            clientDataJSON: Self.base64URLEncode(cred.rawClientDataJSON)
        )
    }

    // MARK: — Passkey assertion (sign-in)

    struct PasskeyAssertionStartOptions {
        let challengeB64URL: String
        let allowedCredentialIdsB64URL: [String]
    }

    struct PasskeyAssertionResult {
        let credentialId: String         // base64url
        let authenticatorData: String    // base64url
        let clientDataJSON: String       // base64url
        let signature: String            // base64url
        let userHandle: String?          // base64url
    }

    /// Present the passkey sign-in sheet. Pass `preferImmediately: true`
    /// to attempt an auto-fill style sheet (best for the SignIn
    /// screen's "Sign in with passkey" button).
    func assertPasskey(options: PasskeyAssertionStartOptions, preferImmediately: Bool = false) async throws -> PasskeyAssertionResult {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: passkeyRpId)
        guard let challengeData = Self.base64URLDecode(options.challengeB64URL) else {
            throw EusoAuthError.malformedPasskeyOptions
        }
        let request = provider.createCredentialAssertionRequest(challenge: challengeData)
        if !options.allowedCredentialIdsB64URL.isEmpty {
            request.allowedCredentials = options.allowedCredentialIdsB64URL.compactMap { idB64 in
                Self.base64URLDecode(idB64).map {
                    ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
                }
            }
        }

        let auth = try await perform(requests: [request], preferImmediately: preferImmediately)

        guard let cred = auth.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw EusoAuthError.unexpectedPasskeyResponse
        }
        return PasskeyAssertionResult(
            credentialId: Self.base64URLEncode(cred.credentialID),
            authenticatorData: Self.base64URLEncode(cred.rawAuthenticatorData),
            clientDataJSON: Self.base64URLEncode(cred.rawClientDataJSON),
            signature: Self.base64URLEncode(cred.signature),
            userHandle: cred.userID.map(Self.base64URLEncode)
        )
    }

    // MARK: — Controller plumbing

    private func perform(requests: [ASAuthorizationRequest], preferImmediately: Bool = false) async throws -> ASAuthorization {
        // Guard against concurrent presentations — ASAuthorization
        // expects exactly one in-flight controller.
        if pendingContinuation != nil {
            throw EusoAuthError.authorizationInProgress
        }
        presentationAnchor = Self.currentKeyWindow()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ASAuthorization, Error>) in
            pendingContinuation = cont
            let controller = ASAuthorizationController(authorizationRequests: requests)
            controller.delegate = self
            controller.presentationContextProvider = self
            if preferImmediately {
                controller.performRequests(options: .preferImmediatelyAvailableCredentials)
            } else {
                controller.performRequests()
            }
        }
    }

    // MARK: — Crypto / encoding helpers

    private static func makeNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = bytes.withUnsafeMutableBufferPointer { ptr in
            SecRandomCopyBytes(kSecRandomDefault, length, ptr.baseAddress!)
        }
        return base64URLEncode(Data(bytes))
    }

    private static func sha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
    static func base64URLDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        let pad = t.count % 4
        if pad > 0 { t.append(String(repeating: "=", count: 4 - pad)) }
        return Data(base64Encoded: t)
    }

    private static func currentKeyWindow() -> ASPresentationAnchor {
        // Find the foreground-active scene's key window; fall back to
        // a fresh UIWindow on the main scene when nothing is visible
        // (e.g. very early app startup).
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene, ws.activationState == .foregroundActive else { continue }
            if let key = ws.windows.first(where: { $0.isKeyWindow }) { return key }
            if let any = ws.windows.first { return any }
        }
        return UIWindow()
    }
}

// MARK: - Errors

enum EusoAuthError: Error, LocalizedError {
    case malformedAppleCredential
    case malformedPasskeyOptions
    case unexpectedPasskeyResponse
    case authorizationInProgress
    case userCanceled
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .malformedAppleCredential: return "Apple didn't return a sign-in token. Try again."
        case .malformedPasskeyOptions:  return "Passkey setup options were invalid. Try again."
        case .unexpectedPasskeyResponse: return "Passkey response shape didn't match. Try again."
        case .authorizationInProgress:  return "Another sign-in is already in progress."
        case .userCanceled:             return "Sign-in canceled."
        case .underlying(let m):        return m
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleAuthProvider: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cont = self.pendingContinuation
            self.pendingContinuation = nil
            cont?.resume(returning: authorization)
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cont = self.pendingContinuation
            self.pendingContinuation = nil
            // ASAuthorizationError.canceled is the routine cancel path —
            // surface a friendlier error so the UI can no-op silently.
            if let asErr = error as? ASAuthorizationError, asErr.code == .canceled {
                cont?.resume(throwing: EusoAuthError.userCanceled)
            } else {
                cont?.resume(throwing: EusoAuthError.underlying(error.localizedDescription))
            }
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthProvider: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Read the anchor that was captured on the main actor when
        // perform() set up the continuation. UIWindow is `Sendable`-
        // adjacent in practice; this is the standard pattern.
        let anchor = MainActor.assumeIsolated { presentationAnchor ?? UIWindow() }
        return anchor
    }
}
