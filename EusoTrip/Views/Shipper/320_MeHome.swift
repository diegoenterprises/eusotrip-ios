//
//  320_MeHome.swift
//  EusoTrip — Shipper · ME tab home (Arc J).
//
//  Identity hero (uses `shippers.getProfile` + `getStats`) + tier ladder
//  + footer cells linking to every ME-section subscreen.
//

import SwiftUI

struct MeHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MeHomeBody() } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                    NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                    NavSlot(label: "Me", systemImage: "person", isCurrent: true),
                ],
                orbState: .idle
            )
        }
    }
}

private struct MeHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var profile: ShipperAPI.Profile? = nil
    @State private var stats: ShipperAPI.Stats? = nil
    @State private var loading = true
    /// MeDetailContainer route to surface as a bottom sheet. Used by
    /// the new INTEL group ("Shipper Intel" → role-aware news feed,
    /// "The Haul" → gamification surface). The route enum is the
    /// canonical Driver-side surface; the views inside read
    /// `session.user?.role` and key off the role enum, so a shipper
    /// gets a shipper-prioritized feed (news.ts ROLE_CATEGORIES) and
    /// a shipper-context Haul lobby out of the same machinery.
    @State private var detailRoute: MeDetailRoute? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let p = profile { hero(p) }
                if let s = stats { tierCard(s) }
                cellGroup(title: "ACCOUNT", cells: [
                    ("person.circle", "Profile", .screen("202")),
                    ("pencil.circle", "Edit profile", .screen("322")),
                    ("rosette",        "Tier detail", .screen("323")),
                ])
                cellGroup(title: "INTEL", cells: [
                    ("newspaper.fill",   "Shipper Intel", .detail(.news)),
                    ("trophy.fill",      "The Haul",      .detail(.haul)),
                    ("exclamationmark.bubble", "Disputes", .detail(.disputes)),
                ])
                cellGroup(title: "EUSOWALLET", cells: [
                    ("wallet.pass.fill", "EusoWallet", .screen("290")),
                    ("creditcard",       "Settlements", .screen("292")),
                    ("creditcard.and.123", "Payment methods", .screen("295")),
                    ("doc.text",         "Statements", .screen("297")),
                    ("leaf",             "Sustainability", .screen("298")),
                    ("chart.bar",        "Reports", .screen("299")),
                ])
                cellGroup(title: "NETWORK", cells: [
                    ("person.3.fill",   "Catalyst directory", .screen("280")),
                    ("star.fill",       "Catalyst scorecards", .screen("213")),
                    ("doc.text.image",  "RFPs", .screen("380")),
                    ("doc.append",      "Contracts", .screen("382")),
                    ("phone.fill",      "Contacts", .screen("209")),
                ])
                cellGroup(title: "COMPLIANCE", cells: [
                    ("shield.lefthalf.filled", "Compliance",      .screen("324")),
                    ("checkmark.shield",       "Insurance",        .screen("325")),
                    ("doc.text",                "FMCSA SAFER",     .screen("326")),
                    ("triangle.fill",          "Hazmat audit",     .screen("327")),
                    ("exclamationmark.bubble", "Freight claims",   .screen("219")),
                ])
                cellGroup(title: "SETTINGS", cells: [
                    ("gear",            "Settings",         .screen("211")),
                    ("bell",            "ESang prefs",      .screen("319")),
                    ("questionmark.circle", "Help",         .screen("347")),
                    ("doc.plaintext",   "Legal",            .screen("348")),
                    ("rectangle.portrait.and.arrow.right", "Sign out", .screen("_logout")),
                ])
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .sheet(item: $detailRoute) { route in
            MeDetailContainer(route: route)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    /// Cell action — either swap to an in-app shipper screen or
    /// surface a Driver-side `MeDetailContainer` route (news, haul).
    /// Keeps the cell-group caller flat ("Profile" → screen("202"),
    /// "Shipper Intel" → detail(.news)) without branching at every
    /// row.
    private enum CellAction {
        case screen(String)
        case detail(MeDetailRoute)
    }

    private func hero(_ p: ShipperAPI.Profile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(initials(p.companyName.isEmpty ? p.contactName : p.companyName))
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 64, height: 64).background(LinearGradient.diagonal).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(dashIfEmpty(p.companyName)).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text(dashIfEmpty(p.contactName)).font(EType.body).foregroundStyle(palette.textSecondary)
                    Text("USDOT \(dashIfEmpty(p.dotNumber)) · MC \(dashIfEmpty(p.mcNumber))").font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
            if p.verified {
                Text("VERIFIED").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
            }
        }
    }

    private func tierCard(_ s: ShipperAPI.Stats) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "TIER", icon: "rosette")
            LifecycleRow(label: "Total loads",        value: "\(s.totalLoads)")
            LifecycleRow(label: "Total spend",        value: "$\(s.totalSpend)")
            LifecycleRow(label: "On-time delivery",   value: "\(s.onTimeDeliveryRate)%")
            LifecycleRow(label: "Preferred catalysts", value: "\(s.preferredCatalysts)")
        }
    }

    private func cellGroup(title: String, cells: [(String, String, CellAction)]) -> some View {
        LifecycleCard {
            LifecycleSection(label: title, icon: "list.bullet")
            ForEach(cells, id: \.1) { (icon, label, action) in
                Button {
                    switch action {
                    case .screen(let screenId):
                        NotificationCenter.default.post(
                            name: .eusoShipperNavSwap, object: nil,
                            userInfo: ["screenId": screenId]
                        )
                    case .detail(let route):
                        detailRoute = route
                    }
                } label: {
                    HStack {
                        Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                        Text(label).font(EType.body).foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                    }
                    .padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }
    }

    private func initials(_ s: String) -> String {
        s.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }

    private func load() async {
        do {
            async let p: ShipperAPI.Profile = EusoTripAPI.shared.shipper.getProfile()
            async let st: ShipperAPI.Stats   = EusoTripAPI.shared.shipper.getStats()
            profile = try await p
            stats = (try? await st)
        } catch { /* tolerate */ }
        loading = false
    }
}

#Preview("320 · Me · Night") { MeHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320 · Me · Afternoon") { MeHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
