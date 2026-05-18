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
    @EnvironmentObject private var session: EusoTripSession
    @State private var showPasskeys: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                section(title: "PREFERENCES", cells: [
                    ("bell", "Notification preferences", "343"),
                    ("doc.on.doc", "Lane templates", "341"),
                    ("sparkles", "eSang preferences", "319"),
                ])
                // SECURITY section — Passkeys gets a custom row that
                // opens the dedicated management sheet (rather than a
                // NotificationCenter screenId hop) so the WebAuthn
                // Face-ID prompt can present from a known anchor.
                securitySection
                section(title: "SUPPORT + LEGAL", cells: [
                    ("questionmark.circle", "Help & support", "347"),
                    ("doc.plaintext", "Legal", "348"),
                    ("trash", "Data export + delete account", "349"),
                ])
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .sheet(isPresented: $showPasskeys) {
            PasskeysManagementView()
                .environment(\.palette, palette)
                .environmentObject(session)
        }
    }

    /// SECURITY section — Passkeys + the screen-ID-routed rows.
    /// Mirrors `section(...)` rendering for the legacy rows so the
    /// visual treatment stays consistent; the Passkeys row breaks
    /// out into a button bound to a sheet because the WebAuthn
    /// system prompt needs a presentation anchor in this view's
    /// lifecycle, which NotificationCenter screen-swaps don't give.
    private var securitySection: some View {
        LifecycleCard {
            LifecycleSection(label: "SECURITY", icon: "list.bullet")
            Button { showPasskeys = true } label: {
                HStack {
                    Image(systemName: "key.viewfinder").foregroundStyle(LinearGradient.diagonal)
                    Text("Passkeys").font(EType.body).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            // Carry the existing rows verbatim — same NotificationCenter
            // post pattern used elsewhere on this screen.
            ForEach([
                ("lock.shield", "Active sessions", "344"),
                ("key.fill", "Two-factor auth", "345"),
                ("rectangle.stack.badge.person.crop", "Connected apps + API tokens", "346"),
            ], id: \.1) { (icon, label, screen) in
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
