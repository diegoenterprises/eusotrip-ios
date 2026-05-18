//
//  102_MeContacts.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Contacts)
//
//  Screen 102 · Me · Contacts — driver's cross-platform contact
//  book. Every shipper rep, dispatcher, broker agent, mechanic
//  partner, and fellow driver the driver interacts with through
//  EusoTrip surfaces here. Tap-to-call / tap-to-email right from
//  the row; favorites pin the contacts the driver leans on most.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Summary + list ship from `contacts.getSummary` +
//      `contacts.list` — MCP-verified at
//      `frontend/server/routers/contacts.ts`.
//    • Search / role filter / favorites filter all round-trip
//      to the server.
//    • Toggle-favorite fires `contacts.toggleFavorite`.
//    • No fabricated names, phones, or companies — every row
//      comes from the `users` × `companies` join.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on favorites + call CTA.
//         Brand.warning on filter-active chips.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeContacts: View {
    @Environment(\.palette) var palette
    @StateObject private var store = ContactsStore()

    private let roleFilters: [(label: String, raw: String?)] = [
        ("All",        nil),
        ("Drivers",    "driver"),
        ("Shippers",   "shipper"),
        ("Catalysts",  "catalyst"),
        ("Brokers",    "broker"),
        ("Dispatch",   "dispatch"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                summaryStrip
                searchBar
                filterRow
                contactsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .onChange(of: store.typeFilter) { _, _ in Task { await store.refresh() } }
        .onChange(of: store.favoritesOnly) { _, _ in Task { await store.refresh() } }
        // RealtimeService → contacts refresh when new partners onboard
        // through dispatch or new shipper/broker contacts land.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refresh() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Contacts")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Shippers · dispatch · brokers · fellow drivers")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Summary strip

    private var summaryStrip: some View {
        let s = store.summary
        return HStack(spacing: Space.s2) {
            summaryTile(label: "TOTAL",    value: "\(s?.total ?? 0)",    gradient: true)
            summaryTile(label: "SHIPPERS", value: "\(s?.shippers ?? 0)", gradient: false)
            summaryTile(label: "CATALYSTS", value: "\(s?.catalysts ?? 0)", gradient: false)
            summaryTile(label: "DRIVERS",  value: "\(s?.drivers ?? 0)",  gradient: false)
        }
    }

    private func summaryTile(label: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(gradient
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.textTertiary)
            TextField("Search by name or company", text: $store.query)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .autocorrectionDisabled()
                .onChange(of: store.query) { _, _ in
                    store.scheduleQuery()
                }
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                    store.scheduleQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
        )
    }

    // MARK: Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                Button {
                    store.favoritesOnly.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.favoritesOnly ? "star.fill" : "star")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Favorites")
                            .font(EType.caption)
                    }
                    .foregroundStyle(store.favoritesOnly
                                     ? AnyShapeStyle(Color.white)
                                     : AnyShapeStyle(palette.textSecondary))
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(store.favoritesOnly
                                       ? AnyShapeStyle(LinearGradient.diagonal)
                                       : AnyShapeStyle(palette.tintNeutral.opacity(0.55)))
                    )
                }
                .buttonStyle(.plain)

                ForEach(roleFilters, id: \.label) { role in
                    let selected = store.typeFilter == role.raw
                    Button {
                        store.typeFilter = role.raw
                    } label: {
                        Text(role.label)
                            .font(EType.caption)
                            .foregroundStyle(selected
                                             ? AnyShapeStyle(LinearGradient.diagonal)
                                             : AnyShapeStyle(palette.textSecondary))
                            .padding(.horizontal, Space.s3)
                            .padding(.vertical, 6)
                            .overlay(
                                Capsule().stroke(
                                    selected ? Color.clear : palette.textTertiary.opacity(0.5),
                                    lineWidth: 1
                                )
                            )
                            .background(
                                Capsule().fill(selected
                                               ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                                               : AnyShapeStyle(Color.clear))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Contacts list

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if store.contacts.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "person.2",
                    title: "No contacts match",
                    subtitle: store.query.isEmpty
                        ? "Your directory populates as you accept loads, message dispatch, and pair with shippers. New contacts land here automatically."
                        : "No one matches “\(store.query).” Try a company name or different role filter."
                )
            } else {
                ForEach(store.contacts) { c in
                    contactRow(c)
                }
            }
        }
    }

    private func contactRow(_ c: ContactsAPI.Contact) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            avatar(c)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(c.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    roleBadge(c.type)
                }
                if let company = c.company, !company.isEmpty {
                    Text(company)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                if let city = c.address?.city, let st = c.address?.state,
                   !city.isEmpty, !st.isEmpty {
                    Text("\(city), \(st)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            Spacer()

            HStack(spacing: Space.s2) {
                if let phone = c.phone, !phone.isEmpty {
                    callButton(phone)
                }
                if let email = c.email, !email.isEmpty {
                    emailButton(email)
                }
                favoriteButton(for: c)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func avatar(_ c: ContactsAPI.Contact) -> some View {
        let initials = c.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0) }
            .joined()
            .uppercased()
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(avatarTint(c.type).opacity(0.22))
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(avatarTint(c.type))
        }
        .frame(width: 44, height: 44)
    }

    private func avatarTint(_ type: String) -> Color {
        switch type.lowercased() {
        case "shipper":   return Brand.info
        case "catalyst":  return Brand.success
        case "dispatch":  return Brand.warning
        case "broker":    return Brand.magenta
        case "driver":    return Brand.info
        default:          return palette.textSecondary
        }
    }

    private func roleBadge(_ type: String) -> some View {
        let label = type.isEmpty
            ? "CONTACT"
            : type.replacingOccurrences(of: "_", with: " ").uppercased()
        let tint = avatarTint(type)
        return Text(label)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
    }

    private func callButton(_ phone: String) -> some View {
        Button {
            let digits = phone.filter { $0.isNumber || $0 == "+" }
            if let url = URL(string: "tel:\(digits)"),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(LinearGradient.diagonal))
        }
        .buttonStyle(.plain)
    }

    private func emailButton(_ email: String) -> some View {
        Button {
            if let url = URL(string: "mailto:\(email)"),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        } label: {
            Image(systemName: "envelope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func favoriteButton(for c: ContactsAPI.Contact) -> some View {
        Button {
            Task { await store.toggleFavorite(c) }
        } label: {
            Image(systemName: c.favorite ? "star.fill" : "star")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.favorite
                                 ? AnyShapeStyle(LinearGradient.diagonal)
                                 : AnyShapeStyle(palette.textTertiary))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        Text("Contacts update in real time as you interact on the platform. Favoriting a row pins it for quick access during active trips.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }
}

// MARK: - Screen wrapper

struct MeContactsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeContacts()
        } nav: {
            BottomNav(
                leading: driverNavLeading_102(),
                trailing: driverNavTrailing_102(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_102() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_102() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("102 · Contacts · Night") {
    MeContactsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("102 · Contacts · Afternoon") {
    MeContactsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
