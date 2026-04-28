//
//  366_ForceUpdate.swift
//  EusoTrip — Shipper · Force update (Arc M).
//

import SwiftUI

struct ForceUpdateScreen: View {
    let theme: Theme.Palette
    var minimumVersion: String = "—"
    var body: some View {
        Shell(theme: theme) { ForceUpdateBody(minVersion: minimumVersion) } nav: { shipperLifecycleNav() }
    }
}

private struct ForceUpdateBody: View {
    @Environment(\.palette) private var palette
    let minVersion: String

    private var installed: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            Image(systemName: "arrow.up.circle.fill").font(.system(size: 48, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("Update required").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("EusoTrip needs the latest build to keep your loads, settlements, and ESang secure.")
                .font(EType.body).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            LifecycleCard {
                LifecycleRow(label: "Installed", value: installed)
                LifecycleRow(label: "Required",  value: minVersion)
            }
            .padding(.horizontal, 14)
            Spacer()
            Button {
                if let u = URL(string: "itms-apps://itunes.apple.com/app/id6448492283") { UIApplication.shared.open(u) }
            } label: {
                Text("Open App Store").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("366 · Force update · Night") { ForceUpdateScreen(theme: Theme.dark, minimumVersion: "2.0.0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("366 · Force update · Afternoon") { ForceUpdateScreen(theme: Theme.light, minimumVersion: "2.0.0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
