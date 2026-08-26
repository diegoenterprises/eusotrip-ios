//
//  074E_ELDConnect.swift
//  EusoTrip — Driver · Compliance · ELD device connect (standalone Shell wrapper).
//
//  Founder report 2026-05-05: "there is nowhere to log into the eld
//  and connect eld device." `ELDIntegrationView` already exists as a
//  full-featured panel (provider picker for Samsara / Motive /
//  Geotab / Powerfleet / Zonar / Lytx / Netradyne / Verizon Connect
//  / Azuga / Solera / Trimble) but it was only reachable from a
//  detail sheet — never from the canonical Me hub. This screen
//  surfaces it as its own destination registered under id "074E"
//  and added to the driver Compliance hub catalog.
//

import SwiftUI

struct ELDConnectScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ConnectedAppsBody(
                includedCategories: ["operational_eld"],
                surfaceTitle: "ELD + fleet telemetry",
                surfaceSummary: "Authorize the provider account that already owns your fleet data. EusoTrip activates it only after credentials, entitlement, health, and first synchronization are verified.",
                showsJourney: true,
                showsAdaptation: false,
                showsTokens: false
            )
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
}

#Preview("074E · ELD Connect · Night") {
    ELDConnectScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("074E · ELD Connect · Afternoon") {
    ELDConnectScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
