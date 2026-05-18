//
//  361_LocationPermission.swift
//  EusoTrip — Shipper · Location permission rationale (Arc M).
//

import SwiftUI
import CoreLocation

private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    func request() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }
}

struct LocationPermissionScreen: View {
    let theme: Theme.Palette
    @State private var delegate = LocationDelegate()
    var body: some View {
        PermissionRationaleScreen(
            theme: theme,
            title: "Location",
            eyebrow: "Shipper · Location",
            icon: "location.fill",
            message: "Location lets the app surface a Live Activity for your in-transit loads, geofence pre-arrival pings, and accurate ETA recalcs.",
            bullets: [
                "Live Activity ETA on Lock Screen + Dynamic Island",
                "Geofence enter/exit alerts (30-min and at-gate)",
                "Trip-aware eSang recommendations",
                "Used only when a load is active, never sold or shared",
            ],
            onGrant: { delegate.request() }
        )
    }
}

#Preview("361 · Location · Night") { LocationPermissionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("361 · Location · Afternoon") { LocationPermissionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
