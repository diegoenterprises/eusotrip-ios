//
//  367_AccountSuspended.swift
//  EusoTrip — Shipper · Account suspended (Arc M).
//

import SwiftUI

struct AccountSuspendedScreen: View {
    let theme: Theme.Palette
    var reason: String = "Account is under review."
    var body: some View {
        Shell(theme: theme) { SuspendedBody(reason: reason) } nav: { shipperLifecycleNav() }
    }
}

private struct SuspendedBody: View {
    @Environment(\.palette) private var palette
    let reason: String

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            Image(systemName: "exclamationmark.octagon.fill").font(.system(size: 48, weight: .heavy)).foregroundStyle(Brand.danger)
            Text("Account suspended").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(reason).font(EType.body).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 32).fixedSize(horizontal: false, vertical: true)
            LifecycleCard(accentDanger: true) {
                LifecycleSection(label: "WHAT TO DO", icon: "phone.bubble.left")
                Text("Email support@eusotrip.com or escalate from the in-app dispatcher line. Active loads remain visible but mutations are paused while review runs.")
                    .font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            Spacer()
            Button { if let u = URL(string: "mailto:support@eusotrip.com") { UIApplication.shared.open(u) } } label: {
                Text("Email support").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("367 · Suspended · Night") { AccountSuspendedScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("367 · Suspended · Afternoon") { AccountSuspendedScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
