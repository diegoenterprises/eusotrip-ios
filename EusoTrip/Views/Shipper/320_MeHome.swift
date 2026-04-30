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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let p = profile { hero(p) }
                if let s = stats { tierCard(s) }
                cellGroup(title: "ACCOUNT", cells: [
                    ("person.circle", "Profile", "202"),
                    ("pencil.circle", "Edit profile", "322"),
                    ("rosette",        "Tier detail", "323"),
                ])
                cellGroup(title: "EUSOWALLET", cells: [
                    ("wallet.pass.fill", "EusoWallet", "290"),
                    ("creditcard",       "Settlements", "292"),
                    ("creditcard.and.123", "Payment methods", "295"),
                    ("doc.text",         "Statements", "297"),
                    ("leaf",             "Sustainability", "298"),
                    ("chart.bar",        "Reports", "299"),
                ])
                cellGroup(title: "NETWORK", cells: [
                    ("person.3.fill",   "Catalyst directory", "280"),
                    ("star.fill",       "Catalyst scorecards", "213"),
                    ("doc.text.image",  "RFPs", "380"),
                    ("doc.append",      "Contracts", "382"),
                    ("phone.fill",      "Contacts", "209"),
                ])
                cellGroup(title: "COMPLIANCE", cells: [
                    ("shield.lefthalf.filled", "Compliance",      "324"),
                    ("checkmark.shield",       "Insurance",        "325"),
                    ("doc.text",                "FMCSA SAFER",     "326"),
                    ("triangle.fill",          "Hazmat audit",     "327"),
                    ("exclamationmark.bubble", "Freight claims",   "219"),
                ])
                cellGroup(title: "SETTINGS", cells: [
                    ("gear",            "Settings",         "211"),
                    ("bell",            "ESang prefs",      "319"),
                    ("questionmark.circle", "Help",         "347"),
                    ("doc.plaintext",   "Legal",            "348"),
                    ("rectangle.portrait.and.arrow.right", "Sign out", "_logout"),
                ])
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
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

    private func cellGroup(title: String, cells: [(String, String, String)]) -> some View {
        LifecycleCard {
            LifecycleSection(label: title, icon: "list.bullet")
            ForEach(cells, id: \.1) { (icon, label, screenId) in
                Button {
                    if screenId == "_logout" {
                        NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "_logout"])
                    } else {
                        NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screenId])
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
