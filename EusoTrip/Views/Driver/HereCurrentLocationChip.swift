//
//  HereCurrentLocationChip.swift
//  EusoTrip — "where am I right now?" address chip backed by HERE
//  Geocoding & Search v7 (reverse-geocode endpoint).
//
//  Uses `DriverLocationResolver.shared` for the live CoreLocation
//  fix and `HereGeocodingClient.shared.reverseGeocode(at:)` to
//  resolve the fix to a human-readable street + city + state line.
//
//  Placement:
//    • 035 En Route Drive — under the bottom summary card (so the
//      driver sees the actual road + cross-street ESANG is routing
//      against, even when turn-by-turn is muted).
//    • 050 Next Beat Live — under the destination header (for the
//      "ending here" cross-street).
//
//  Behaviour:
//    • Fetches once on appear; refreshes when the live coordinate
//      moves more than ~0.5 mi (the HERE address granularity).
//    • Hides cleanly when CoreLocation is denied OR HERE returns
//      empty — the doctrine elsewhere in the app is "no fake
//      data", so we don't render a placeholder.
//    • Render is a single-line gradient pill, capped at 1 line so
//      it never reflows the host card.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

@MainActor
final class HereCurrentLocationStore: ObservableObject {
    @Published private(set) var line: String = ""

    private var lastFetchAt: CLLocationCoordinate2D?

    /// Refresh when the chip appears or when the host's current fix
    /// has moved enough to justify a re-resolve.
    func refresh() async {
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            line = ""
            return
        }
        if let prev = lastFetchAt, distance(prev, coord) < 800 {
            // < ~0.5 mi — stay with the cached label.
            return
        }
        do {
            let items = try await HereGeocodingClient.shared.reverseGeocode(
                at: coord,
                limit: 1
            )
            guard let first = items.first else {
                line = ""
                return
            }
            lastFetchAt = coord
            line = format(first)
        } catch {
            // Quiet fail — chip hides until the next refresh succeeds.
            line = ""
        }
    }

    private func format(_ item: HereGeocodeItem) -> String {
        let a = item.address
        // Prefer the street + city · state pattern; fall back to the
        // HERE-provided `label` (full address) if the structured fields
        // aren't populated for this fix.
        let street = [a.houseNumber, a.street]
            .compactMap { $0 }
            .joined(separator: " ")
        let cityState = [a.city, a.stateCode ?? a.state]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        if !street.isEmpty && !cityState.isEmpty {
            return "\(street) · \(cityState)"
        }
        if !cityState.isEmpty { return cityState }
        return a.label ?? ""
    }

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

struct HereCurrentLocationChip: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = HereCurrentLocationStore()

    var body: some View {
        Group {
            if store.line.isEmpty {
                EmptyView()
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(store.line)
                        .font(EType.micro).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Text("EUSOTRIP")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(palette.bgCardSoft)
                .overlay(
                    Capsule()
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(Capsule())
            }
        }
        .task { await store.refresh() }
    }
}

#Preview("HereCurrentLocationChip · Dark") {
    HereCurrentLocationChip()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .padding()
        .background(Theme.dark.bgPage)
}

#Preview("HereCurrentLocationChip · Light") {
    HereCurrentLocationChip()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .padding()
        .background(Theme.light.bgPage)
}
