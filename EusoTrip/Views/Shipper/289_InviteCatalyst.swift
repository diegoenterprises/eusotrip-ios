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
    @State private var sentToEmail: String = ""
    // Honest delivery state (ASC AMNzdpJ3): server now reports whether the
    // email actually left ACS. false/nil = invite exists but delivery is
    // unconfirmed, so we surface the signup link for direct sharing.
    @State private var emailConfirmed = false
    @State private var shareUrl: String = ""
    @State private var linkCopied = false
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
                .onChange(of: email) { _, _ in
                    // Once the user starts a fresh invite, retire the prior
                    // success banner so a stale "sent" never misleads them.
                    if sent { sent = false }
                }
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

    @ViewBuilder
    private var successCard: some View {
        if emailConfirmed {
            LifecycleCard(accentGradient: true) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invite sent").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text(sentToEmail.isEmpty
                             ? "The carrier will receive an email shortly."
                             : "We emailed your referral link to \(sentToEmail). The carrier will receive it shortly.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            LifecycleCard(accentGradient: true) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "link.circle.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invite created").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text("Email delivery could not be confirmed. Share your referral link directly:")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !shareUrl.isEmpty {
                            Text(shareUrl)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(2).truncationMode(.middle)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.bgCard.opacity(0.6))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            HStack(spacing: 8) {
                                Button {
                                    UIPasteboard.general.string = shareUrl
                                    withAnimation(.easeOut(duration: 0.12)) { linkCopied = true }
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        withAnimation(.easeOut(duration: 0.12)) { linkCopied = false }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: linkCopied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10, weight: .heavy))
                                        Text(linkCopied ? "Copied" : "Copy link")
                                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(LinearGradient.diagonal)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }.buttonStyle(.plain)
                                ShareLink(item: shareUrl) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 10, weight: .heavy))
                                        Text("Share")
                                            .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                                    }
                                    .foregroundStyle(palette.textPrimary)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(palette.bgCard.opacity(0.6))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
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
        struct Out: Decodable {
            let success: Bool
            let invitationId: String?
            let emailSent: Bool?
            let signupUrl: String?
        }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "referrals.inviteCarrier",
                input: In(email: email, dotNumber: dotNumber.isEmpty ? nil : dotNumber, note: note.isEmpty ? nil : note)
            )
            sentToEmail = email
            // Only claim "we emailed" when the server confirms delivery;
            // otherwise surface the signup link for direct sharing.
            emailConfirmed = out.emailSent == true
            shareUrl = out.signupUrl ?? ""
            linkCopied = false
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
