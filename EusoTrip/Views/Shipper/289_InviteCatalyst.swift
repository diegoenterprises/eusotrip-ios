//
//  289_InviteCatalyst.swift
//  EusoTrip — Shipper · Invite catalyst to platform (Arc F).
//

import SwiftUI

struct InviteCatalystScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { InviteCatalystBody() } nav: { shipperLifecycleNav() }
    }
}

private struct InviteCatalystBody: View {
    @Environment(\.palette) private var palette
    @State private var email: String = ""
    @State private var dotNumber: String = ""
    @State private var note: String = ""
    @State private var sending = false
    @State private var sent = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { successCard }
                if let err = actionError { errorCard(err) }
                fieldsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · INVITE A CARRIER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Invite a carrier").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Send a referral link with your account number pre-attached. Carrier joins as a new account, your referral credit lands automatically.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "INVITE DETAILS", icon: "person.crop.circle.badge.plus")
            field(label: "Email", binding: $email, placeholder: "carrier@example.com")
            field(label: "USDOT (optional)", binding: $dotNumber, placeholder: "e.g. 1234567")
            field(label: "Note (optional)", binding: $note, placeholder: "Add a personal note")
        }
    }

    private func field(label: String, binding: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain).autocorrectionDisabled(true).textInputAutocapitalization(.never)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var successCard: some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(LinearGradient.diagonal)
                Text("Invite sent. The carrier will receive an email shortly.").font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
    }

    private var ctaRow: some View {
        Button {
            Task { await send() }
        } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Sending…" : "Send invite")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || email.isEmpty)
    }

    private func send() async {
        sending = true; actionError = nil
        struct In: Encodable { let email: String; let dotNumber: String?; let note: String? }
        struct Out: Decodable { let success: Bool; let invitationId: String? }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation(
                "referrals.inviteCarrier",
                input: In(email: email, dotNumber: dotNumber.isEmpty ? nil : dotNumber, note: note.isEmpty ? nil : note)
            )
            sent = true
            email = ""; dotNumber = ""; note = ""
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("289 · Invite · Night") {
    InviteCatalystScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("289 · Invite · Afternoon") {
    InviteCatalystScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
