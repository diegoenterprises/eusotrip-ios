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

struct RoleHomeIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eSangMorningBriefCard()

            // Always-visible bespoke weather surface — owns its own fetch and
            // honest empty states (data / loading / enable-location /
            // unavailable). Replaces the previous gated WeatherCard that
            // vanished whenever the snapshot was nil.
            HomeWeatherWidget()
        }
    }
}
