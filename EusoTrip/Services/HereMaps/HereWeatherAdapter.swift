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
    /// `latitude` is the queried coordinate's latitude (the caller has the
    /// pickup/delivery lat at the call site) — threads the sky-engine
    /// geometry so the destination scene picks the right season/hemisphere.
    static func fromHereWeather(
        _ place: HereWeatherPlace,
        city: String,
        latitude: Double? = nil
    ) -> WeatherSnapshot? {
        guard let obs = place.observations?.current else { return nil }
        // A partial HERE payload can carry an observation block with a NULL
        // temperature; without a real reading we return nil rather than
        // fabricating tempF=0 — a fake 0° would poison downstream freeze/ambient
        // peril flags (REEFER · FREEZE RISK 0°) on temp-controlled loads.
        guard obs.temperatureFahrenheit != nil || obs.temperature != nil else { return nil }

        // Temperature — HereWeatherClient requests `units=imperial`.
        // The live v3 payload usually places Fahrenheit in `temperature`
        // and omits `temperatureFahrenheit`, so do not convert the fallback.
        let tempF: Int = {
            if let f = obs.temperatureFahrenheit {
                return Int(f.rounded())
            }
            if let f = obs.temperature {
                return Int(f.rounded())
            }
            return 0
        }()

        // Wind — with `units=imperial`, live v3 reports mph in
        // `windSpeed` and often omits `windSpeedMph`.
        guard let windMph: Int = {
            if let mph = obs.windSpeedMph { return Int(mph.rounded()) }
            if let mph = obs.windSpeed { return Int(mph.rounded()) }
            if let kmh = obs.windSpeedKmh { return Int((kmh * 0.621371).rounded()) }
            return nil
        }() else { return nil }

        // Visibility — HERE returns miles in en-US, km otherwise. Nil when
        // the observation omitted it (em-dash doctrine — a fabricated 0
        // falsely tripped the LOW VIS hazard).
        let visibilityMi: Int? = obs.visibility.map { Int($0.rounded()) }

        // Condition + SF Symbol pairing. HERE doesn't ship SF
        // Symbols directly — we map the icon id / description string
        // onto the closest system glyph so the card matches the
        // WeatherKit path's visual vocabulary.
        let condition = obs.description ?? "—"
        let symbol = Self.symbol(for: obs)

        // Next-alert line — first meaningful change in the next 6
        // hourly slots, or today's H/L. Severe bulletins now ride the
        // card's dedicated alert ribbon (snapshot.alerts), so this pill
        // stays a forward-looking condition nudge.
        let nextAlert: String? = {
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

        // NWS bulletins → the CAP severity ladder the ribbon renders.
        let alerts: [WeatherSnapshot.SevereAlert] = {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            return (place.nwsAlerts?.alerts ?? []).map { a in
                WeatherSnapshot.SevereAlert(
                    event: (a.type ?? "Weather alert").capitalized,
                    severity: WeatherSnapshot.AlertSeverity(capString: a.severity),
                    headline: a.description,
                    endsAt: a.validUntilTimeLocal.flatMap { iso.date(from: $0) }
                )
            }
            .sorted { $0.severity.rank > $1.severity.rank }
        }()

        // Accent — severe NWS alerts promote to warn; heavy wind or
        // low visibility promotes to watch.
        let accent: WeatherSnapshot.Accent = {
            if alerts.contains(where: { $0.severity >= .severe }) {
                return .warn
            }
            if windMph >= 25 || (visibilityMi ?? .max) <= 2 {
                return .watch
            }
            return .calm
        }()

        // Feels-like ("comfort" in HERE vocabulary) + humidity. Like
        // temperature, the imperial payload often uses `comfort`.
        let feelsLikeF: Int? = {
            if let f = obs.comfortFahrenheit { return Int(f.rounded()) }
            if let f = obs.comfort { return Int(f.rounded()) }
            return nil
        }()
        let humidityPct: Int? = obs.humidity.map { Int($0.rounded()) }

        // Next-12-hours band from `forecastHourly` — same product the
        // platform's hereMaps.weatherAt proc normalises server-side.
        let hourly: [WeatherSnapshot.HourlyForecast] = {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            let cutoff = Date().addingTimeInterval(-1800)
            var out: [WeatherSnapshot.HourlyForecast] = []
            for h in (place.hourlyForecasts?.forecasts ?? []) {
                guard out.count < 12 else { break }
                guard
                    let ts = h.time,
                    let date = iso.date(from: ts),
                    date >= cutoff
                else { continue }
                let tempF: Int? = {
                    if let f = h.temperatureFahrenheit { return Int(f.rounded()) }
                    if let f = h.temperature { return Int(f.rounded()) }
                    return nil
                }()
                guard let tempF else { continue }
                out.append(WeatherSnapshot.HourlyForecast(
                    date: date,
                    tempF: tempF,
                    symbol: Self.dailySymbol(for: h.iconName ?? h.description ?? ""),
                    precipChancePct: h.precipitationProbability.map { Int($0.rounded()) },
                    windMph: (h.windSpeedMph ?? h.windSpeed).map { Int($0.rounded()) }
                ))
            }
            return out
        }()
        let precipChancePct: Int? = hourly.first?.precipChancePct

        // 6-day daily look-ahead. HERE ships weekday labels out of
        // the box — we keep them when present and synthesize from
        // the ISO date otherwise.
        let daily: [DailyForecast] = {
            let src = ((place.dailyForecasts?.forecasts ?? []) + (place.extendedDailyForecasts?.forecasts ?? [])).prefix(6)
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
                guard let high = d.highTemperatureFahrenheit ?? d.highTemperature ?? d.temperature else { continue }
                let low = d.lowTemperatureFahrenheit ?? d.lowTemperature ?? high
                let hi = Int(high.rounded())
                let lo = Int(low.rounded())
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

        var snap = WeatherSnapshot(
            city: city,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visibilityMi,
            condition: condition,
            symbol: symbol,
            nextAlert: nextAlert,
            accent: accent,
            daily: daily,
            feelsLikeF: feelsLikeF,
            humidityPct: humidityPct,
            precipChancePct: precipChancePct,
            hourly: hourly,
            alerts: alerts
        )
        // Adaptive-card wiring (weather-audit 2026-07-09): without these the
        // hero card went NON-adaptive exactly when a load was active — the
        // glyph/sky engine key off `weatherCode` (0 = unknown-cloud), the
        // attribution read "live source", "updated Nm ago" vanished, and the
        // sky scene lost its season/hemisphere geometry. Mirrors the NWS
        // composer's tail.
        snap.weatherCode = WeatherIcons.code(forSymbol: symbol)
        snap.dataSource = .here
        snap.observedAt = Date()
        snap.latitude = latitude
        return snap
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
