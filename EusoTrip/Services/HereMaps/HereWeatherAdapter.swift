//
//  HereWeatherAdapter.swift
//  EusoTrip — Converts HERE Destination Weather responses into the
//  `WeatherSnapshot` shape the existing `WeatherCard` on 010 Home
//  already renders.
//
//  Routing policy (2026-04-24, user direction):
//    "keep weather kit only switching to destination weather only
//     when its an active load or upcoming load."
//
//  So the Home dashboard stays on WeatherKit for "where I'm parked
//  right now" when the driver is between loads, and switches to
//  HERE Destination Weather only when an active / upcoming load
//  means the driver cares about the route or destination
//  conditions more than the local rooftop. This adapter is the
//  bridge — it takes a `HereWeatherPlace` for the destination coord
//  and returns a `WeatherSnapshot` the existing card renders
//  verbatim.
//
//  Powered by ESANG AI™.
//

import Foundation
import SwiftUI

extension WeatherSnapshot {

    /// Build a driver-facing snapshot from a HERE Destination Weather
    /// place + a human city label. The label is passed in instead of
    /// read from `place.address` because callers usually already
    /// have a clean display string (the load's delivery-city field)
    /// and HERE's address block skips over state short-codes for
    /// some international addresses.
    static func fromHereWeather(
        _ place: HereWeatherPlace,
        city: String
    ) -> WeatherSnapshot? {
        guard let obs = place.observations?.current else { return nil }

        // Temperature — HERE ships both scales; prefer the explicit
        // Fahrenheit field when available (en-US locale), else
        // convert from Celsius.
        let tempF: Int = {
            if let f = obs.temperatureFahrenheit {
                return Int(f.rounded())
            }
            if let c = obs.temperature {
                return Int((c * 9.0 / 5.0 + 32).rounded())
            }
            return 0
        }()

        // Wind — HERE ships `windSpeedMph` in en-US; fall back to
        // km/h conversion for non-US locales.
        let windMph: Int = {
            if let mph = obs.windSpeedMph {
                return Int(mph.rounded())
            }
            if let kmh = obs.windSpeedKmh {
                return Int((kmh * 0.621371).rounded())
            }
            if let ms = obs.windSpeed {
                return Int((ms * 2.23694).rounded())
            }
            return 0
        }()

        // Visibility — HERE returns miles in en-US, km otherwise.
        let visibilityMi: Int = {
            guard let v = obs.visibility else { return 0 }
            // Assume US payloads return miles; everything else km.
            return Int(v.rounded())
        }()

        // Condition + SF Symbol pairing. HERE doesn't ship SF
        // Symbols directly — we map the icon id / description string
        // onto the closest system glyph so the card matches the
        // WeatherKit path's visual vocabulary.
        let condition = obs.description ?? "—"
        let symbol = Self.symbol(for: obs)

        // Next-alert line — first meaningful change in the next 6
        // hourly slots, or today's H/L.
        let nextAlert: String? = {
            if let nws = place.nwsAlerts?.alerts?.first {
                let kind = (nws.type ?? "Alert").uppercased()
                return "⚠︎ \(kind) · tap for details"
            }
            let horizon = (place.hourlyForecasts?.forecasts ?? []).prefix(6)
            for (i, h) in horizon.enumerated() {
                if let desc = h.description,
                   desc.lowercased() != (obs.description ?? "").lowercased() {
                    let offset = i + 1
                    return "\(offset)h · \(desc.lowercased())"
                }
            }
            if let d0 = place.dailyForecasts?.forecasts.first,
               let hi = d0.highTemperatureFahrenheit,
               let lo = d0.lowTemperatureFahrenheit {
                return "today · H \(Int(hi.rounded()))° / L \(Int(lo.rounded()))°"
            }
            return nil
        }()

        // Accent — severe NWS alerts promote to warn; heavy wind or
        // low visibility promotes to watch.
        let accent: WeatherSnapshot.Accent = {
            if let alerts = place.nwsAlerts?.alerts {
                if alerts.contains(where: { ($0.severity ?? "").lowercased() == "severe" || ($0.severity ?? "").lowercased() == "extreme" }) {
                    return .warn
                }
            }
            if windMph >= 25 || visibilityMi <= 2 {
                return .watch
            }
            return .calm
        }()

        // 5-day daily look-ahead. HERE ships weekday labels out of
        // the box — we keep them when present and synthesize from
        // the ISO date otherwise.
        let daily: [DailyForecast] = {
            let src = (place.dailyForecasts?.forecasts ?? []).prefix(5)
            var out: [DailyForecast] = []
            let iso = ISO8601DateFormatter()
            let fallback = DateFormatter()
            fallback.dateFormat = "yyyy-MM-dd"
            for (i, d) in src.enumerated() {
                let date: Date = {
                    if let s = d.date {
                        if let d1 = iso.date(from: s) { return d1 }
                        if let d2 = fallback.date(from: s) { return d2 }
                    }
                    return Calendar.current.date(
                        byAdding: .day, value: i, to: Date()
                    ) ?? Date()
                }()
                let label: String = {
                    if i == 0 { return "Today" }
                    if let w = d.weekday, !w.isEmpty {
                        return String(w.prefix(3))
                    }
                    let f = DateFormatter()
                    f.dateFormat = "EEE"
                    return f.string(from: date)
                }()
                let hi = Int((d.highTemperatureFahrenheit ?? 0).rounded())
                let lo = Int((d.lowTemperatureFahrenheit ?? 0).rounded())
                let sym = Self.dailySymbol(for: d.iconName ?? d.description ?? "")
                out.append(
                    DailyForecast(
                        date: date,
                        weekdayLabel: label,
                        highF: hi,
                        lowF: lo,
                        symbol: sym,
                        condition: d.description ?? "—",
                        precipChance: d.precipitationProbability.map { $0 / 100.0 }
                    )
                )
            }
            return out
        }()

        return WeatherSnapshot(
            city: city,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visibilityMi,
            condition: condition,
            symbol: symbol,
            nextAlert: nextAlert,
            accent: accent,
            daily: daily
        )
    }

    // MARK: - Symbol mapping

    /// Maps a HERE observation into the closest SF Symbol. HERE's
    /// `iconName` strings follow their own vocabulary ("sunny",
    /// "mostly_sunny", "thunderstorms", etc.) — we lower-case and
    /// match on substrings so minor spelling / suffix variations
    /// still land on the right glyph.
    private static func symbol(for obs: HereWeatherObservation) -> String {
        let key = (obs.iconName ?? obs.description ?? "").lowercased()
        if key.isEmpty { return "cloud.sun.fill" }
        if key.contains("thunder") || key.contains("storm") { return "cloud.bolt.rain.fill" }
        if key.contains("snow") || key.contains("blizzard") || key.contains("sleet") { return "snowflake" }
        if key.contains("rain") || key.contains("shower") { return "cloud.rain.fill" }
        if key.contains("fog") || key.contains("mist") || key.contains("haze") { return "cloud.fog.fill" }
        if key.contains("windy") || key.contains("breezy") { return "wind" }
        if key.contains("mostly_cloudy") || key.contains("mostly cloudy") { return "cloud.fill" }
        if key.contains("partly") { return "cloud.sun.fill" }
        if key.contains("cloudy") || key.contains("overcast") { return "cloud.fill" }
        if key.contains("sunny") || key.contains("clear") { return "sun.max.fill" }
        if key.contains("night") || key.contains("moon") { return "moon.fill" }
        return "cloud.sun.fill"
    }

    private static func dailySymbol(for hint: String) -> String {
        let key = hint.lowercased()
        if key.contains("thunder") { return "cloud.bolt.fill" }
        if key.contains("snow") { return "snowflake" }
        if key.contains("rain") { return "cloud.rain.fill" }
        if key.contains("partly") { return "cloud.sun.fill" }
        if key.contains("cloud") { return "cloud.fill" }
        if key.contains("sunny") || key.contains("clear") { return "sun.max.fill" }
        return "cloud.sun.fill"
    }
}
