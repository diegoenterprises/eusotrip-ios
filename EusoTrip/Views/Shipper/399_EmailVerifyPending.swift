//
//  399_EmailVerifyPending.swift
//  EusoTrip — Shipper · Email verification pending (Arc B+ / Arc A onboarding).
//

import SwiftUI

struct EmailVerifyPendingScreen: View {
    let theme: Theme.Palette
    var email: String = ""
    var body: some View {
        Shell(theme: theme) { EmailVerifyBody(email: email) } nav: { shipperLifecycleNav() }
    }
}

private struct EmailVerifyBody: View {
    @Environment(\.palette) private var palette
    let email: String
    @State private var resending: Bool = false
    @State private var resent: Bool = false
    @State private var actionError: String? = nil
    @State private var checking: Bool = false

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            Image(systemName: "envelope.badge").font(.system(size: 56, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("Check your email").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("We sent a verification link to \(email.isEmpty ? "your inbox" : email). Tap it to finish setup.").font(EType.body).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 32).fixedSize(horizontal: false, vertical: true)
            if resent { LifecycleCard(accentGradient: true) { Text("Verification email re-sent.").font(EType.body).foregroundStyle(palette.textPrimary) }.padding(.horizontal, 14) }
            if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }.padding(.horizontal, 14) }
            Spacer()
            VStack(spacing: 10) {
                Button { Task { await checkVerified() } } label: {
                    HStack(spacing: 6) {
                        if checking { ProgressView().tint(.white) }
                        Text(checking ? "Checking…" : "I've verified — continue").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain).disabled(checking)
                Button { Task { await resend() } } label: {
                    HStack(spacing: 6) {
                        if resending { ProgressView().tint(palette.textPrimary) }
                        Text(resending ? "Resending…" : "Resend email").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }.buttonStyle(.plain).disabled(resending)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resend() async {
        resending = true; actionError = nil
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.api.mutation("auth.resendEmailVerification", input: ["": ""] as [String: String])
            resent = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        resending = false
    }

    private func checkVerified() async {
        checking = true; actionError = nil
        struct Out: Decodable { let verified: Bool }
        do {
            let r: Out = try await EusoTripAPI.shared.api.queryNoInput("auth.checkEmailVerified")
            if r.verified {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "200"])
            } else {
                actionError = "Not yet verified. Tap the link in your email."
            }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        checking = false
    }
}

#Preview("399 · Email verify · Night") { EmailVerifyPendingScreen(theme: Theme.dark, email: "shipper@eusotrip.com").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("399 · Email verify · Afternoon") { EmailVerifyPendingScreen(theme: Theme.light, email: "shipper@eusotrip.com").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
