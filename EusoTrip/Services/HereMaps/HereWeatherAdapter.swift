//
//  HereWeatherAdapter.swift
//  EusoTrip — Converts HERE Destination Weather responses into the
//  route/lane `WeatherSnapshot` shape used by the active-load strip.
//
//  Locked authority split: HERE owns route endpoints, corridor hazards, and
//  ETA impact. It never replaces the ambient WeatherKit current/hourly/daily/
//  alerts/solar hero. This adapter supplies only the route-aware lane strip.
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
    /// `latitude`/`longitude` are the queried coordinate (the caller has the
    /// pickup/delivery pair at the call site). They let a retained HERE
    /// observation recompute the destination's present solar state after the
    /// provider daylight hint ages, without consulting the device timezone.
    static func fromHereWeather(
        _ place: HereWeatherPlace,
        city: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) -> WeatherSnapshot? {
        guard let obs = place.observations?.current else { return nil }
        // A partial HERE payload can carry an observation block with a NULL
        // temperature; without a real reading we return nil rather than
        // fabricating tempF=0 — a fake 0° would poison downstream freeze/ambient
        // peril flags (REEFER · FREEZE RISK 0°) on temp-controlled loads.
        // Temperature — HereWeatherClient requests `units=imperial`.
        // The live v3 payload usually places Fahrenheit in `temperature`
        // and omits `temperatureFahrenheit`, so do not convert the fallback.
        guard let tempF = WeatherNumeric.roundedInt(
            obs.temperatureFahrenheit ?? obs.temperature,
            allowed: WeatherNumeric.temperatureF
        ) else { return nil }

        // Wind — with `units=imperial`, live v3 reports mph in
        // `windSpeed` and often omits `windSpeedMph`.
        let rawWindMph = obs.windSpeedMph
            ?? obs.windSpeed
            ?? obs.windSpeedKmh.map { $0 * 0.621371 }
        guard let windMph = WeatherNumeric.roundedInt(
            rawWindMph,
            allowed: WeatherNumeric.windMph
        ) else { return nil }

        // Visibility — HERE returns miles in en-US, km otherwise. Nil when
        // the observation omitted it (em-dash doctrine — a fabricated 0
        // falsely tripped the LOW VIS hazard).
        let visibilityMi = WeatherNumeric.roundedInt(
            obs.visibility,
            allowed: WeatherNumeric.visibilityMi
        )

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
               let hi = d0.highTemperatureFahrenheit ?? d0.highTemperature ?? d0.temperature,
               let lo = d0.lowTemperatureFahrenheit ?? d0.lowTemperature,
               let highF = WeatherNumeric.roundedInt(hi, allowed: WeatherNumeric.temperatureF),
               let lowF = WeatherNumeric.roundedInt(lo, allowed: WeatherNumeric.temperatureF) {
                return "today · H \(highF)° / L \(lowF)°"
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
                    endsAt: a.validUntilTimeLocal.flatMap { iso.date(from: $0) },
                    source: "National Weather Service via HERE",
                    detailsURL: nil
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
        let feelsLikeF = WeatherNumeric.roundedInt(
            obs.comfortFahrenheit ?? obs.comfort,
            allowed: WeatherNumeric.temperatureF
        )
        let humidityPct = WeatherNumeric.roundedInt(
            obs.humidity,
            allowed: WeatherNumeric.percent
        )

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
                guard let tempF = WeatherNumeric.roundedInt(
                    h.temperatureFahrenheit ?? h.temperature,
                    allowed: WeatherNumeric.temperatureF
                ) else { continue }
                out.append(WeatherSnapshot.HourlyForecast(
                    date: date,
                    tempF: tempF,
                    symbol: Self.dailySymbol(for: h.iconName ?? h.description ?? ""),
                    precipChancePct: WeatherNumeric.roundedInt(
                        h.precipitationProbability,
                        allowed: WeatherNumeric.percent
                    ),
                    windMph: WeatherNumeric.roundedInt(
                        h.windSpeedMph ?? h.windSpeed,
                        allowed: WeatherNumeric.windMph
                    ),
                    isDaylightHint: Self.daylightHint(h.daylight)
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
                guard let rawDate = d.date,
                      let date = iso.date(from: rawDate) ?? fallback.date(from: rawDate)
                else { continue }
                let label: String = {
                    if i == 0 { return "Today" }
                    if let w = d.weekday, !w.isEmpty {
                        return String(w.prefix(3))
                    }
                    let f = DateFormatter()
                    f.dateFormat = "EEE"
                    return f.string(from: date)
                }()
                guard
                    let high = d.highTemperatureFahrenheit ?? d.highTemperature ?? d.temperature,
                    let low = d.lowTemperatureFahrenheit ?? d.lowTemperature
                else { continue }
                guard
                    let hi = WeatherNumeric.roundedInt(high, allowed: WeatherNumeric.temperatureF),
                    let lo = WeatherNumeric.roundedInt(low, allowed: WeatherNumeric.temperatureF)
                else { continue }
                let sym = Self.dailySymbol(for: d.iconName ?? d.description ?? "")
                out.append(
                    DailyForecast(
                        date: date,
                        weekdayLabel: label,
                        highF: hi,
                        lowF: lo,
                        symbol: sym,
                        condition: d.description ?? "—",
                        precipChance: WeatherNumeric.roundedInt(
                            d.precipitationProbability,
                            allowed: WeatherNumeric.percent
                        ).map { Double($0) / 100.0 }
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
        // Route-card wiring. Coordinates allow solar geometry to be recomputed
        // without borrowing the device timezone; freshness is provider-issued
        // only and remains nil if HERE omitted its timestamp.
        snap.weatherCode = WeatherIcons.code(forSymbol: symbol)
        snap.dataSource = .here
        snap.observedAt = Self.providerDate(obs.utcTime)
        snap.latitude = latitude
        snap.longitude = longitude
        snap.isNightHint = Self.daylightHint(obs.daylight).map { !$0 }
            ?? WeatherIcons.daylightHint(forSymbol: symbol).map { !$0 }
        return snap
    }

    // MARK: - Symbol mapping

    private static func providerDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return fractional.date(from: raw) ?? plain.date(from: raw)
    }

    /// Maps a HERE observation into the closest SF Symbol. HERE's
    /// `iconName` strings follow their own vocabulary ("sunny",
    /// "mostly_sunny", "thunderstorms", etc.) — we lower-case and
    /// match on substrings so minor spelling / suffix variations
    /// still land on the right glyph.
    private static func symbol(for obs: HereWeatherObservation) -> String {
        let key = (obs.iconName ?? obs.description ?? "").lowercased()
        if key.isEmpty { return "cloud.sun.fill" }
        let isNight = key.contains("night") || key.contains("moon")
        if key.contains("thunder") || key.contains("storm") { return "cloud.bolt.rain.fill" }
        if key.contains("snow") || key.contains("blizzard") || key.contains("sleet") { return "snowflake" }
        if key.contains("rain") || key.contains("shower") { return "cloud.rain.fill" }
        if key.contains("fog") || key.contains("mist") || key.contains("haze") { return "cloud.fog.fill" }
        if key.contains("windy") || key.contains("breezy") { return "wind" }
        if key.contains("mostly_cloudy") || key.contains("mostly cloudy") { return "cloud.fill" }
        if key.contains("partly") { return isNight ? "cloud.moon.fill" : "cloud.sun.fill" }
        if key.contains("cloudy") || key.contains("overcast") { return "cloud.fill" }
        if isNight { return "moon.fill" }
        if key.contains("sunny") || key.contains("clear") { return "sun.max.fill" }
        return "cloud.sun.fill"
    }

    private static func dailySymbol(for hint: String) -> String {
        let key = hint.lowercased()
        let isNight = key.contains("night") || key.contains("moon")
        if key.contains("thunder") { return "cloud.bolt.fill" }
        if key.contains("snow") { return "snowflake" }
        if key.contains("rain") { return "cloud.rain.fill" }
        if key.contains("partly") { return isNight ? "cloud.moon.fill" : "cloud.sun.fill" }
        if key.contains("cloud") { return "cloud.fill" }
        if isNight { return "moon.fill" }
        if key.contains("sunny") || key.contains("clear") { return "sun.max.fill" }
        return "cloud.sun.fill"
    }

    /// HERE Destination Weather uses a compact daylight discriminator. Be
    /// deliberately strict: unknown/new provider values stay nil and fall
    /// through to coordinate-based solar calculation instead of guessing.
    private static func daylightHint(_ raw: String?) -> Bool? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "d", "day", "daylight", "true", "1": return true
        case "n", "night", "nighttime", "false", "0": return false
        default: return nil
        }
    }
}
