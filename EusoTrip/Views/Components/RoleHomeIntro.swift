//
//  RoleHomeIntro.swift
//  EusoTrip — Canonical Home lead-in for every role.
//
//  Doctrine: Driver 010 is the baseline. Every role's Home opens with
//      ESANG brief  →  Weather  →  role-specific widgets.
//
//  This component renders the first two cards as one reusable unit:
//    • eSangMorningBriefCard  — the "ESANG brief" top coaching card,
//                               role/vertical-aware, auto-loads on appear.
//    • WeatherCard            — live snapshot from WeatherService.shared.
//                               Falls back to a neutral "Enable location"
//                               CTA when CoreLocation is denied/restricted.
//                               Silently omits the card when WeatherKit is
//                               momentarily unavailable (no fake data).
//
//  Usage from any role home body:
//      VStack(alignment: .leading, spacing: Space.s4) {
//          RoleHomeIntro()                  // ← morning brief + weather
//          // …role-specific widgets follow…
//      }
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RoleHomeIntro: View {
    @Environment(\.palette) private var palette
    @State private var snapshot: WeatherSnapshot? = nil
    @State private var availability: Availability = .pending

    enum Availability: Equatable { case pending, live, needsLocation, unavailable }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eSangMorningBriefCard()

            if let s = snapshot {
                WeatherCard(snapshot: s)
            } else if availability == .needsLocation {
                enableLocationCard
            }
        }
        .task { await fetch() }
    }

    private var enableLocationCard: some View {
        Button {
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
        } label: {
            HStack(alignment: .center, spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 48, height: 48)
                    Image(systemName: "location.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable location for live weather")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Grant location to see local conditions, visibility, and route weather.")
                        .font(EType.micro)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
    }

    private func fetch() async {
        let service = WeatherService.shared
        let s = await service.fetchCurrent()
        await MainActor.run {
            if let s = s {
                self.snapshot = s
                self.availability = .live
            } else {
                self.snapshot = nil
                switch service.authorizationStatus {
                case .denied, .restricted:                self.availability = .needsLocation
                case .notDetermined:                       self.availability = .pending
                case .authorizedWhenInUse, .authorizedAlways: self.availability = .unavailable
                @unknown default:                          self.availability = .unavailable
                }
            }
        }
    }
}
