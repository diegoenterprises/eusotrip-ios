//
//  060L_TheHaulLobby.swift
//  EusoTrip — Driver · The Haul · Lobby (standalone full-screen).
//
//  Founder report 2026-05-05: "theres no lobby access for the
//  driver useer role its missing." The HaulLobbyTab existed only
//  inside the 4-tab Haul detail sheet (Lobby / Missions / Rewards /
//  Leaderboard); this screen surfaces it as its own destination
//  reachable from the 067f Me-Haul hub catalog.
//

import SwiftUI

struct TheHaulLobbyScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                HaulLobbyTab()
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        } nav: {
            BottomNav(
                leading: [
                    NavSlot(label: "Home",   systemImage: "house.fill",        isCurrent: false),
                    NavSlot(label: "Trips",  systemImage: "shippingbox.fill",  isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "My Loads", systemImage: "shippingbox.fill",  isCurrent: false),
                    NavSlot(label: "Me",     systemImage: "person.fill",       isCurrent: true),
                ],
                orbState: .idle
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("THE HAUL · LOBBY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Lobby")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(EnvPalette().textPrimary)
            Text("Real-time chat with drivers, dispatch, fleet ops, EusoTrip staff.")
                .font(EType.caption)
                .foregroundStyle(EnvPalette().textSecondary)
        }
    }

    /// Resolves the active palette without an EnvironmentObject —
    /// keeps the header preview-friendly when invoked outside the
    /// `Shell` chain.
    private func EnvPalette() -> Theme.Palette { theme }
}

#Preview("060L · Driver Haul Lobby · Night") {
    TheHaulLobbyScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("060L · Driver Haul Lobby · Afternoon") {
    TheHaulLobbyScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
