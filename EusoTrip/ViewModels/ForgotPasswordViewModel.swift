//
//  ForgotPasswordViewModel.swift
//  EusoTrip — Forgot-password + reset-password state.
//

import Foundation
import SwiftUI

@MainActor
final class ForgotPasswordViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case submitting
        case error(String)
        case sent
    }

    @Published var email: String = ""
    @Published var phase: Phase = .idle

    var canSubmit: Bool { email.contains("@") && email.contains(".") }

    func submit(api: EusoTripAPI = .shared) async {
        phase = .submitting
        do {
            _ = try await api.auth.forgotPassword(email: email)
            phase = .sent
        } catch EusoTripAPIError.trpcError(let msg) {
            phase = .error(msg)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}

@MainActor
final class ResetPasswordViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case submitting
        case error(String)
        case done
    }

    @Published var token: String = ""
    @Published var newPassword: String = ""
    @Published var confirmPassword: String = ""
    @Published var phase: Phase = .idle

    var canSubmit: Bool {
        !token.isEmpty && newPassword.count >= 8 && newPassword == confirmPassword
    }

    func submit(api: EusoTripAPI = .shared) async {
        phase = .submitting
        do {
            _ = try await api.auth.resetPassword(token: token, newPassword: newPassword)
            phase = .done
        } catch EusoTripAPIError.trpcError(let msg) {
            phase = .error(msg)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}
