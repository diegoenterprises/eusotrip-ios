//
//  365_NetworkErrorRetry.swift
//  EusoTrip — Shipper · Network error / retry (Arc M).
//

import SwiftUI

struct NetworkErrorRetryScreen: View {
    let theme: Theme.Palette
    var message: String = "We couldn't reach the EusoTrip server."
    var onRetry: () -> Void = {}
    var body: some View {
        Shell(theme: theme) { ErrorBody(message: message, onRetry: onRetry) } nav: { shipperLifecycleNav() }
    }
}

private struct ErrorBody: View {
    @Environment(\.palette) private var palette
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            Image(systemName: "wifi.slash").font(.system(size: 48, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("Couldn't connect").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(message).font(EType.body).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            Button { onRetry() } label: {
                Text("Retry").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "364"])
            } label: {
                Text("View offline mode").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("365 · Network error · Night") { NetworkErrorRetryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("365 · Network error · Afternoon") { NetworkErrorRetryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
