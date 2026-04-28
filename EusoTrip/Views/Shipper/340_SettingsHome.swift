//
//  340_SettingsHome.swift
//  EusoTrip — Shipper · Settings home (Arc K).
//

import SwiftUI

struct SettingsHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { SettingsHomeBody() } nav: { shipperLifecycleNav() }
    }
}

private struct SettingsHomeBody: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                section(title: "PREFERENCES", cells: [
                    ("bell", "Notification preferences", "343"),
                    ("doc.on.doc", "Lane templates", "341"),
                    ("sparkles", "ESang preferences", "319"),
                ])
                section(title: "SECURITY", cells: [
                    ("lock.shield", "Active sessions", "344"),
                    ("key.fill", "Two-factor auth", "345"),
                    ("rectangle.stack.badge.person.crop", "Connected apps + API tokens", "346"),
                ])
                section(title: "SUPPORT + LEGAL", cells: [
                    ("questionmark.circle", "Help & support", "347"),
                    ("doc.plaintext", "Legal", "348"),
                    ("trash", "Data export + delete account", "349"),
                ])
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "gear").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SETTINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settings").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func section(title: String, cells: [(String, String, String)]) -> some View {
        LifecycleCard {
            LifecycleSection(label: title, icon: "list.bullet")
            ForEach(cells, id: \.1) { (icon, label, screen) in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screen])
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
}

#Preview("340 · Settings · Night") { SettingsHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("340 · Settings · Afternoon") { SettingsHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
