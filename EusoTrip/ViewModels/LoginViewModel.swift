//
//  LoginViewModel.swift
//  EusoTrip — Sign-in state machine.
//
//  Phases:
//    idle         → email / password entry
//    submitting   → awaiting auth.login
//    twoFactor    → 2FA challenge (TOTP or SMS)
//    error(msg)   → inline banner; stays on current form
//    success      → session takes over
//

import Foundation
import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case submitting
        case twoFactor(method: String) // "totp" | "sms"
        case error(String)
        case success
    }

    @Published var email: String = ""
    @Published var password: String = ""
    @Published var twoFactorCode: String = ""
    @Published var phase: Phase = .idle

    var emailError: String? {
        guard !email.isEmpty else { return nil }
        return email.contains("@") && email.contains(".") ? nil : "Enter a valid email"
    }

    var passwordError: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 6 ? nil : "Minimum 6 characters"
    }

    var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && emailError == nil && passwordError == nil
    }

    var canSubmitTOTP: Bool {
        let t = twoFactorCode.trimmingCharacters(in: .whitespaces)
        return t.count == 6 && t.allSatisfy(\.isNumber)
    }

    // MARK: Actions

    func submit(session: EusoTripSession) async {
        phase = .submitting
        do {
            let resp = try await session.signIn(email: email, password: password)
            if resp.success {
                phase = .success
            } else if resp.requiresTwoFactor == true {
                phase = .twoFactor(method: resp.method ?? "totp")
            } else {
                phase = .error(resp.message ?? "Sign-in failed")
            }
        } catch EusoTripAPIError.unauthenticated {
            phase = .error("Invalid email or password")
        } catch EusoTripAPIError.trpcError(let msg) {
            phase = .error(msg)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func submitTwoFactor(session: EusoTripSession) async {
        phase = .submitting
        do {
            let resp = try await session.signIn(
                email: email,
                password: password,
                twoFactorCode: twoFactorCode.trimmingCharacters(in: .whitespaces)
            )
            if resp.success {
                phase = .success
            } else {
                phase = .error(resp.message ?? "Invalid 2FA code")
            }
        } catch EusoTripAPIError.trpcError(let msg) {
            phase = .error(msg)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func clearError() {
        if case .error = phase { phase = .idle }
    }
}
