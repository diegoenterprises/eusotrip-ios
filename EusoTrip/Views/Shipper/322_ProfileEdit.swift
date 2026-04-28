//
//  322_ProfileEdit.swift
//  EusoTrip — Shipper · Profile edit (Arc J).
//  Calls `shippers.updateProfile` (server gap §5 — surfaces honest
//  error if not yet wired).
//

import SwiftUI

struct ProfileEditScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ProfileEditBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ProfileEditBody: View {
    @Environment(\.palette) private var palette
    @State private var contactName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var website: String = ""
    @State private var loading = true
    @State private var sending = false
    @State private var saved = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Profile updated.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                fieldsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · EDIT PROFILE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Edit profile").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DETAILS", icon: "person")
            field("Contact name", text: $contactName)
            field("Email", text: $email)
            field("Phone", text: $phone)
            field("Address", text: $address)
            field("Website", text: $website)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(label, text: text)
                .textFieldStyle(.plain).autocorrectionDisabled(label != "Contact name")
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(palette.bgCard.opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var ctaRow: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Saving…" : "Save profile").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending)
    }

    private func load() async {
        do {
            let p = try await EusoTripAPI.shared.shippers.getProfile()
            contactName = p.contactName; email = p.email; phone = p.phone
            address = p.address; website = p.website
        } catch { /* tolerate */ }
        loading = false
    }

    private func save() async {
        sending = true; actionError = nil
        struct In: Encodable { let contactName: String; let email: String; let phone: String; let address: String; let website: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.api.mutation("shippers.updateProfile", input: In(contactName: contactName, email: email, phone: phone, address: address, website: website))
            saved = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("322 · Profile edit · Night") { ProfileEditScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("322 · Profile edit · Afternoon") { ProfileEditScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
