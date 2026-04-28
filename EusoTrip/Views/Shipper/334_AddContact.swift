//
//  334_AddContact.swift
//  EusoTrip — Shipper · Add contact (Arc J).
//

import SwiftUI

struct AddContactScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AddContactBody() } nav: { shipperLifecycleNav() }
    }
}

private struct AddContactBody: View {
    @Environment(\.palette) private var palette
    @State private var name: String = ""
    @State private var role: String = ""
    @State private var company: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var sending = false
    @State private var saved = false
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if saved { LifecycleCard(accentGradient: true) { Text("Contact added.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                fieldsCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ADD CONTACT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Add a contact").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var fieldsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DETAILS", icon: "person")
            field("Name", text: $name)
            field("Role", text: $role)
            field("Company", text: $company)
            field("Email", text: $email)
            field("Phone", text: $phone)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(label, text: text)
                .textFieldStyle(.plain)
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
                Text(sending ? "Saving…" : "Add contact").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || name.isEmpty)
    }

    private func save() async {
        sending = true; actionError = nil
        struct In: Encodable { let name: String; let role: String?; let company: String?; let email: String?; let phone: String? }
        struct Out: Decodable { let success: Bool; let contactId: String? }
        do {
            let _ : Out = try await EusoTripAPI.shared.api.mutation("contacts.create", input: In(name: name, role: role.isEmpty ? nil : role, company: company.isEmpty ? nil : company, email: email.isEmpty ? nil : email, phone: phone.isEmpty ? nil : phone))
            saved = true
            name = ""; role = ""; company = ""; email = ""; phone = ""
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("334 · Add contact · Night") { AddContactScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("334 · Add contact · Afternoon") { AddContactScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
