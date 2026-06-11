//
//  WeatherSnapshot.swift
//  EusoTrip — Freight-grade weather payload for the home dashboards.
//
//  Wire-plan authority:
//    • Apple WeatherKit (primary, on-device)
//    • api.weather.gov (NWS ground-truth fallback, US)
//    • Open-Meteo (keyless last resort, non-US)
//    • HERE Destination Weather v3 (route/lane weather when a load is
//      active) — shapes mirror server/services/here/destinationWeather.ts
//      (observation · forecastHourly · forecast7days · alerts).
//
//  Level-100 doctrine (2026-06-11): every value is live or em-dash.
//  Nothing here is fabricated — optional fields stay nil when the
//  upstream source didn't supply them and the card renders "—".
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
    var daily: [DailyForecast] = []

    // ── Level-100 depth (all optional → em-dash when absent) ────────

    /// "Feels like" — heat index / wind chill. Nil when the source
    /// didn't supply an apparent temperature.
    var feelsLikeF: Int? = nil
    /// Relative humidity 0–100. Nil when unavailable.
    var humidityPct: Int? = nil
    /// Wind gust in mph — the number a high-profile trailer cares
    /// about. Nil when the source reports no gust.
    var windGustMph: Int? = nil
    /// Chance of precipitation in the next hour, 0–100.
    var precipChancePct: Int? = nil
    /// Next ~12 hours, hourly. Empty when the source had no hourly block.
    var hourly: [HourlyForecast] = []
    /// Active severe-weather bulletins (NWS-style severity). Empty =
    /// no active alerts — which is itself live information.
    var alerts: [SevereAlert] = []

    /// One hour in the hourly band.
    struct HourlyForecast: Hashable, Identifiable {
        let date: Date
        let tempF: Int
        /// SF Symbol for the hour's condition.
        let symbol: String
        /// 0–100, nil when not supplied.
        let precipChancePct: Int?
        /// mph, nil when not supplied.
        let windMph: Int?

        var id: Date { date }

        /// "3PM"
        var hourLabel: String {
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("ha")
            return f.string(from: date)
        }

        /// "40%" or nil (hidden below the 10% noise floor).
        var precipDisplay: String? {
            guard let p = precipChancePct, p >= 10 else { return nil }
            return "\(p)%"
        }
    }

    /// One active severe-weather bulletin. Severity vocabulary follows
    /// NWS CAP ("Minor" | "Moderate" | "Severe" | "Extreme") — the same
    /// strings HERE Destination Weather passes through on `nwsAlerts`
    /// and api.weather.gov returns on /alerts/active.
    struct SevereAlert: Hashable, Identifiable {
        /// "Winter Storm Warning"
        let event: String
        let severity: AlertSeverity
        /// Long-form headline when the source supplies one.
        let headline: String?
        /// When the bulletin expires — nil when open-ended/unknown.
        let endsAt: Date?

        var id: String { "\(event)-\(endsAt?.timeIntervalSince1970 ?? 0)" }

        /// "until 6 PM" or nil.
        var untilDisplay: String? {
            guard let endsAt else { return nil }
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("ha")
            return "until \(f.string(from: endsAt))"
        }
    }

    /// NWS CAP severity ladder.
    enum AlertSeverity: String, Hashable, Comparable {
        case minor, moderate, severe, extreme, unknown

        init(capString: String?) {
            switch (capString ?? "").lowercased() {
            case "minor":    self = .minor
            case "moderate": self = .moderate
            case "severe":   self = .severe
            case "extreme":  self = .extreme
            default:         self = .unknown
            }
        }

        var rank: Int {
            switch self {
            case .unknown:  return 0
            case .minor:    return 1
            case .moderate: return 2
            case .severe:   return 3
            case .extreme:  return 4
            }
        }

        var color: Color {
            switch self {
            case .extreme, .severe: return Brand.danger
            case .moderate:         return Brand.warning
            case .minor, .unknown:  return Brand.info
            }
        }

        var label: String { rawValue.uppercased() }

        static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
            lhs.rank < rhs.rank
        }
    }

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

    /// "Feels 91°" or "Feels —".
    var feelsLikeDisplay: String {
        guard let f = feelsLikeF else { return "—" }
        return "\(f)°"
    }

    /// "64%" or "—".
    var humidityDisplay: String {
        guard let h = humidityPct else { return "—" }
        return "\(h)%"
    }

    /// "12 mph" or "12 G 28" when gusting meaningfully above sustained.
    var windDisplay: String {
        if let g = windGustMph, g >= windMph + 8 {
            return "\(windMph) G \(g)"
        }
        return "\(windMph) mph"
    }

    /// "12 mph · 9 mi vis"
    var metaDisplay: String {
        "\(windMph) mph · \(visibilityMi) mi vis"
    }

    /// Highest-severity active alert — drives the ribbon.
    var topAlert: SevereAlert? {
        alerts.max(by: { $0.severity.rank < $1.severity.rank })
    }

    // ── Freight thresholds (derived from live values — never invented) ──

    /// Sustained ≥ 25 mph or gusts ≥ 40 mph — the band where a loaded
    /// high-profile van/reefer starts crabbing and an empty one is at
    /// genuine blow-over risk.
    var windHazard: Bool {
        windMph >= 25 || (windGustMph ?? 0) >= 40
    }

    /// Frozen-precip signature: wintry condition text at ≤ 34 °F —
    /// the regime where chain laws can activate on mountain corridors.
    var wintryHazard: Bool {
        let t = condition.lowercased()
        let wintry = t.contains("snow") || t.contains("ice") || t.contains("sleet")
            || t.contains("freezing") || t.contains("blizzard") || t.contains("wintry")
            || t.contains("flurr")
        return wintry && tempF <= 34
    }

    /// Visibility ≤ 2 mi — CMV slow-down territory.
    var visibilityHazard: Bool { visibilityMi <= 2 }
}

// MARK: - LaneWeather — the active load's lane, end to end.

/// Route-aware weather for the driver's active load: live conditions
/// at the pickup and the delivery (HERE Destination Weather v3 — same
/// product set the platform's `hereMaps.weatherAt` / `weatherForRoute`
/// procs normalise server-side). Each point is a full `WeatherSnapshot`
/// so the lane strip and the freight flags read from the same honest
/// pipeline as the hero card.
struct LaneWeather: Hashable {
    struct Point: Hashable {
        /// "PICKUP" | "DELIVERY"
        let role: String
        /// "Laredo, TX"
        let city: String
        let snapshot: WeatherSnapshot
    }

    let origin: Point?
    let destination: Point?
    /// True when the active load is temperature-controlled (cargo type
    /// says reefer/refrigerated) — gates the ambient-extreme flag.
    let isTempControlled: Bool

    var points: [Point] { [origin, destination].compactMap { $0 } }

    var isEmpty: Bool { points.isEmpty }

    /// Highest-severity alert anywhere on the lane.
    var topAlert: WeatherSnapshot.SevereAlert? {
        points
            .compactMap { $0.snapshot.topAlert }
            .max(by: { $0.severity.rank < $1.severity.rank })
    }

    // ── Freight flags — derived strictly from live readings ─────────

    struct FreightFlag: Hashable, Identifiable {
        let id: String
        let icon: String
        let label: String
        let accent: WeatherSnapshot.Accent
    }

    /// The flags a shipper/driver actually acts on. Each one is a
    /// threshold over live data — no invented forecasts:
    ///   • WIND      — sustained ≥ 25 / gusts ≥ 40 anywhere on the lane.
    ///   • CHAINS    — wintry precip at ≤ 34 °F (chain laws may apply).
    ///   • LOW VIS   — ≤ 2 mi at either end.
    ///   • REEFER    — ambient ≥ 85 °F or ≤ 32 °F on a temp-controlled
    ///                 load (unit stress / freeze risk at the docks).
    var flags: [FreightFlag] {
        var out: [FreightFlag] = []
        let snaps = points.map(\.snapshot)

        if snaps.contains(where: { $0.windHazard }) {
            let worstGust = snaps.compactMap(\.windGustMph).max()
            let severe = (worstGust ?? 0) >= 40
            out.append(.init(
                id: "wind",
                icon: "wind",
                label: severe ? "HIGH-PROFILE · GUSTS \(worstGust ?? 0)" : "HIGH-PROFILE WIND",
                accent: severe ? .warn : .watch
            ))
        }
        if snaps.contains(where: { $0.wintryHazard }) {
            out.append(.init(
                id: "chains",
                icon: "snowflake.road.lane",
                label: "ICE/SNOW · CHAIN LAWS MAY APPLY",
                accent: .warn
            ))
        }
        if snaps.contains(where: { $0.visibilityHazard }) {
            out.append(.init(
                id: "vis",
                icon: "eye.trianglebadge.exclamationmark",
                label: "LOW VISIBILITY",
                accent: .watch
            ))
        }
        if isTempControlled {
            let hot = snaps.map(\.tempF).max() ?? 0
            let cold = snaps.map(\.tempF).min() ?? 99
            if hot >= 85 {
                out.append(.init(
                    id: "reefer-hot",
                    icon: "thermometer.sun.fill",
                    label: "REEFER · AMBIENT \(hot)°",
                    accent: .watch
                ))
            } else if cold <= 32 {
                out.append(.init(
                    id: "reefer-cold",
                    icon: "thermometer.snowflake",
                    label: "REEFER · FREEZE RISK \(cold)°",
                    accent: .watch
                ))
            }
        }
        return out
    }
}

// No demo fixtures — weather is always sourced live (WeatherKit → NWS →
// Open-Meteo for the driver's position; HERE Destination Weather for the
// active load's lane). The card simply hides when no service can produce
// a snapshot (permission denied, offline, etc.).
