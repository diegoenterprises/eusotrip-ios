//
//  333_ContactDetail.swift
//  EusoTrip — Shipper · Contact detail (Arc J).
//

import SwiftUI

struct ContactDetailScreen: View {
    let theme: Theme.Palette
    let contactId: String
    var body: some View {
        Shell(theme: theme) { ContactDetailBody(contactId: contactId) } nav: { shipperLifecycleNav() }
    }
}

private struct Contact: Decodable, Hashable {
    let id: String
    let name: String?
    let role: String?
    let company: String?
    let email: String?
    let phone: String?
    let lastInteractionAt: String?
    let loadIds: [String]?
}

private struct ContactDetailBody: View {
    @Environment(\.palette) private var palette
    let contactId: String
    @State private var contact: Contact? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading contact…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let c = contact { detailCard(c); ctaRow(c); historyCard(c) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CONTACT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(contact?.name ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func detailCard(_ c: Contact) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "DETAILS", icon: "person")
            LifecycleRow(label: "Role",     value: dashIfEmpty(c.role))
            LifecycleRow(label: "Company",  value: dashIfEmpty(c.company))
            LifecycleRow(label: "Email",    value: dashIfEmpty(c.email))
            LifecycleRow(label: "Phone",    value: dashIfEmpty(c.phone))
            LifecycleRow(label: "Last seen", value: humanISO(c.lastInteractionAt))
        }
    }

    private func ctaRow(_ c: Contact) -> some View {
        HStack(spacing: 10) {
            if let p = c.phone, !p.isEmpty {
                Button { if let url = URL(string: "tel://\(p.filter(\.isNumber))") { UIApplication.shared.open(url) } } label: {
                    Text("Call").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(LinearGradient.diagonal).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
            if let e = c.email, !e.isEmpty {
                Button { if let url = URL(string: "mailto:\(e)") { UIApplication.shared.open(url) } } label: {
                    Image(systemName: "envelope.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .frame(width: 44, height: 44).background(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func historyCard(_ c: Contact) -> some View {
        if let ids = c.loadIds, !ids.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "RECENT LOADS", icon: "list.bullet")
                ForEach(ids.prefix(10), id: \.self) { id in
                    Button {
                        NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "205", "loadId": id])
                    } label: {
                        HStack {
                            Image(systemName: "shippingbox").foregroundStyle(LinearGradient.diagonal)
                            Text(id).font(EType.body).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                        }
                        .padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let id: String }
        do {
            let c: Contact = try await EusoTripAPI.shared.api.query("contacts.getById", input: In(id: contactId))
            contact = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("333 · Contact · Night") { ContactDetailScreen(theme: Theme.dark, contactId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("333 · Contact · Afternoon") { ContactDetailScreen(theme: Theme.light, contactId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
