//
//  360_PushPermission.swift
//  EusoTrip — Shipper · Push permission rationale (Arc M).
//

import SwiftUI
import UserNotifications

struct PushPermissionScreen: View {
    let theme: Theme.Palette
    var body: some View {
        PermissionRationaleScreen(
            theme: theme,
            title: "Push notifications",
            eyebrow: "Shipper · Push",
            icon: "bell.badge",
            message: "We push you the moment a bid lands, your truck crosses a geofence, or a settlement is paid. Without push, you'll miss time-boxed actions.",
            bullets: [
                "Bid received + eSang recommended",
                "Geofence pre-arrival ping (30 min out)",
                "Load status changes (in transit, delivery, paid)",
                "Settlement disputes + accessorial approvals",
            ],
            onGrant: {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        )
    }
}

#Preview("360 · Push · Night") { PushPermissionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("360 · Push · Afternoon") { PushPermissionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
