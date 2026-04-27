//
//  WeatherSnapshot.swift
//  EusoTrip — Driver-facing weather payload for screen 010 Home dashboard
//
//  Wire-plan authority:
//    • frontend/server/services/here/locationAnalytics.ts  (road-condition)
//    • Apple WeatherKit fallback on device.
//
//  Kept intentionally flat — the DriverHome WeatherCard only needs one
//  current-conditions snapshot + one short forecast line. Richer detail
//  ships with the dedicated weather screen.
//

import Foundation
import SwiftUI

struct WeatherSnapshot: Hashable {
    /// "Meridian, MS"
    let city: String
    /// Current temperature in whole Fahrenheit.
    let tempF: Int
    /// Numeric wind speed in mph.
    let windMph: Int
    /// Visibility in whole miles.
    let visibilityMi: Int
    /// Short human phrase — "Partly cloudy".
    let condition: String
    /// SF Symbol glyph that pairs with the condition (cloud.sun.fill etc.).
    let symbol: String
    /// "5h · light rain · pickup window" — the driver-actionable forecast line.
    let nextAlert: String?
    /// Accent color choice — blue for clear/dry, warning for hazard watch.
    let accent: Accent
    /// 5-day look-ahead rendered on the flip side of the card. First
    /// entry is today — matches the "H 63° / L 56°" line on the front.
    /// Empty when the upstream API didn't return a daily block (which
    /// shouldn't happen but the card handles it gracefully by falling
    /// back to the nextAlert line only).
    var daily: [DailyForecast] = []

    /// A single day in the 5-day look-ahead.
    struct DailyForecast: Hashable, Identifiable {
        /// Midnight in the driver's local timezone for the day this
        /// forecast represents. Used as the list id + label source.
        let date: Date
        /// "Mon" / "Tue" for the week-chip header. "Today" for the
        /// first entry regardless of weekday.
        let weekdayLabel: String
        /// Forecast high in whole Fahrenheit.
        let highF: Int
        /// Forecast low in whole Fahrenheit.
        let lowF: Int
        /// SF Symbol glyph for the day's dominant condition.
        let symbol: String
        /// Short human phrase — "Partly cloudy".
        let condition: String
        /// Chance of precipitation, 0…1. Nil if the upstream API didn't
        /// supply a probability (some WeatherKit responses omit it for
        /// very distant days).
        let precipChance: Double?

        var id: Date { date }

        var highDisplay: String { "\(highF)°" }
        var lowDisplay:  String { "\(lowF)°" }

        /// "30%" or nil.
        var precipDisplay: String? {
            guard let p = precipChance, p > 0.05 else { return nil }
            return "\(Int((p * 100).rounded()))%"
        }
    }

    enum Accent: Hashable {
        case calm
        case watch
        case warn

        var color: Color {
            switch self {
            case .calm:  return Brand.info
            case .watch: return Brand.warning
            case .warn:  return Brand.danger
            }
        }
    }

    /// "72°"
    var tempDisplay: String { "\(tempF)°" }

    /// "12 mph · 9 mi vis"
    var metaDisplay: String {
        "\(windMph) mph · \(visibilityMi) mi vis"
    }
}

// No demo fixtures — weather is always sourced live from Apple WeatherKit
// via `WeatherService.fetchCurrent()` and paired with CoreLocation for the
// user's actual position. The card simply hides when the service can't
// produce a snapshot (permission denied, offline, etc.).
