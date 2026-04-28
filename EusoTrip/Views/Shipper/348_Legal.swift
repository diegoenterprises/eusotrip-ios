//
//  348_Legal.swift
//  EusoTrip — Shipper · Legal · TOS / Privacy / OSS (Arc K).
//

import SwiftUI

struct LegalScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LegalBody() } nav: { shipperLifecycleNav() }
    }
}

private struct LegalBody: View {
    @Environment(\.palette) private var palette

    private let docs: [(label: String, url: String)] = [
        ("Terms of Service", "https://eusotrip.com/legal/tos"),
        ("Privacy Policy",   "https://eusotrip.com/legal/privacy"),
        ("Cookie Policy",    "https://eusotrip.com/legal/cookies"),
        ("Open-source notices", "https://eusotrip.com/legal/oss"),
        ("Compliance attestations", "https://eusotrip.com/legal/compliance"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                LifecycleCard {
                    LifecycleSection(label: "DOCUMENTS", icon: "doc.text")
                    ForEach(docs, id: \.label) { d in
                        Button {
                            if let u = URL(string: d.url) { UIApplication.shared.open(u) }
                        } label: {
                            HStack {
                                Image(systemName: "doc.plaintext").foregroundStyle(LinearGradient.diagonal)
                                Text(d.label).font(EType.body).foregroundStyle(palette.textPrimary)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                            }
                            .padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                }
                LifecycleCard {
                    LifecycleSection(label: "ABOUT THIS APP", icon: "info.circle")
                    LifecycleRow(label: "Eusorone Technologies, Inc.", value: "© 2026")
                    LifecycleRow(label: "Sole author", value: "Mike \"Diego\" Usoro")
                    LifecycleRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.plaintext").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LEGAL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Legal").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }
}

#Preview("348 · Legal · Night") { LegalScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("348 · Legal · Afternoon") { LegalScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
