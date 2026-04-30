//
//  WeatherService.swift
//  EusoTrip — Live weather for screen 010 Driver Home.
//
//  Pipeline:
//    CoreLocation one-shot → CLPlacemark (city) → WeatherKit current + hourly
//    → WeatherSnapshot (imperial units, driver-actionable next-alert line)
//
//  The service is intentionally forgiving: on any failure (permission denied,
//  location timeout, WeatherKit network error) it returns `nil` rather than
//  throwing. The DriverHome WeatherCard then simply doesn't render.
//
//  Requires:
//    • Target capability "WeatherKit" enabled on the App ID (entitlement).
//    • INFOPLIST_KEY_NSLocationWhenInUseUsageDescription set in pbxproj.
//

import Foundation
import CoreLocation
import WeatherKit

@MainActor
final class WeatherService: NSObject, ObservableObject {

    static let shared = WeatherService()

    private let locationManager: CLLocationManager = {
        let m = CLLocationManager()
        // Best accuracy. Earlier passes used km-accuracy → 100m;
        // both still let CoreLocation hand back a cached fix that
        // pulled WeatherKit for the wrong city. `kCLLocationAccuracyBest`
        // forces a fresh GPS reading on almost every requestLocation()
        // call. Trade-off is battery, but weather only fetches on
        // dashboard appear / pull-to-refresh — not constantly.
        m.desiredAccuracy = kCLLocationAccuracyBest
        return m
    }()

    /// Maximum age (in seconds) of a CoreLocation fix we'll accept.
    /// Tightened from 300s → 60s — 5 min was still letting a stale
    /// fix from a prior county leak through when the driver moved
    /// quickly. 60s means within the past minute, the driver hasn't
    /// realistically left the local weather cell.
    private let maxLocationAgeSeconds: TimeInterval = 60

    private let weatherService = WeatherKit.WeatherService.shared

    private var pendingLocation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Exposed status (75th firing, 2026-04-24)
    //
    // DriverHomeViewModel needs to tell the dashboard WHY weather isn't
    // rendering (location denied vs WeatherKit unavailable), so the
    // underlying CLAuthorizationStatus is exposed read-only. Kept
    // `private(set)` equivalent via a computed getter — no public
    // locationManager surface.

    /// Current CoreLocation authorization status for the WeatherService.
    /// Consumers use this to distinguish "needs location" from "weather
    /// momentarily unavailable" so the UI can offer the right CTA.
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    // MARK: - Public

    /// Fetch a single current snapshot for the user's present location.
    /// Returns `nil` on any failure — UI is expected to gracefully hide the
    /// weather card rather than show an error state for this non-critical
    /// dashboard element.
    ///
    /// Flow:
    ///   1. Kick CoreLocation authorization if we haven't asked yet.
    ///   2. Try a one-shot location read with a hard 4-second timeout so
    ///      the simulator (which frequently has no fix) can't stall us.
    ///   3. If no location came back, return nil — callers inspect
    ///      `authorizationStatus` to decide whether to render an
    ///      "Enable location" CTA or silently omit the card. We do NOT
    ///      fall back to a fabricated city any more (this was a Cohort A
    ///      mock before the 75th firing).
    ///
    /// 75th firing (2026-04-24, eusotrip-killers hygiene + fallback C):
    /// dropped the Dallas, TX fallback. Rendering weather for a location
    /// the driver isn't actually at violated §3 "no-mock" and the 2027
    /// motivation "no fake data" pledge. The dashboard's new
    /// `weatherAvailability` state carries the reason up to the view.
    func fetchCurrent() async -> WeatherSnapshot? {
        guard let location = await requestLocationIfNeeded() else {
            return nil
        }

        do {
            let weather = try await weatherService.weather(for: location)
            let placemark = try? await reverseGeocode(location)
            return Self.compose(weather: weather, placemark: placemark)
        } catch {
            // Surface the FULL error in every build (not just DEBUG) so a
            // misconfigured signing / entitlement / portal-capability
            // failure is visible in production crash logs / Xcode
            // console — not silently masked by the NWS fallback.
            // WeatherKit-specific failure modes we've seen:
            //   • Code 2: missing entitlement on the bundle ID
            //   • Code 3: app not signed by a team that owns the bundle
            //   • Code 4: WeatherKit not enabled on developer.apple.com
            //              for this bundle ID (user must add the
            //              capability in the dev portal — code can't fix)
            //   • Code 7: signing issue, framework not embedded
            let ns = error as NSError
            print("[WeatherService] WeatherKit fetch failed — domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription) info=\(ns.userInfo)")
            let placemark = try? await reverseGeocode(location)
            // For US locations, prefer NWS (api.weather.gov). NWS pulls
            // from real ground stations + radar — accurate ground truth.
            // Open-Meteo aggregates multiple models and notoriously
            // reports "Thunderstorm code 95" when a single cell exists
            // anywhere in the coverage area, even when the specific
            // point is sunny — exactly what was rendering on the home
            // dashboard for Austin drivers during the past three sunny
            // days.
            let isUS: Bool = {
                guard let p = placemark else { return false }
                let cc = (p.isoCountryCode ?? "").uppercased()
                return cc == "US" || cc == "USA" || cc.isEmpty
            }()
            if isUS {
                if let nws = try? await fetchNWS(location: location, placemark: placemark) {
                    return nws
                }
            }
            // Non-US fallback (or NWS failed) — Open-Meteo as last
            // resort. Better imperfect data than no card at all.
            return try? await fetchOpenMeteo(location: location, placemark: placemark)
        }
    }

    // MARK: - NWS (api.weather.gov) — US ground-truth fallback

    /// Two-hop NWS query: POST coords → /points → forecast endpoints,
    /// then GET observations from the nearest station. NWS uses real
    /// ground stations + Doppler radar so the "thunderstorm at sunny
    /// noon" mismatch Open-Meteo causes goes away. NWS requires no
    /// API key, just a User-Agent.
    private func fetchNWS(
        location: CLLocation,
        placemark: CLPlacemark?
    ) async throws -> WeatherSnapshot {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        struct PointsResp: Decodable {
            struct Properties: Decodable {
                let observationStations: String
                let forecast: String
                let relativeLocation: RelLoc?
            }
            struct RelLoc: Decodable { let properties: RelLocProps }
            struct RelLocProps: Decodable { let city: String?; let state: String? }
            let properties: Properties
        }
        struct StationsResp: Decodable {
            struct Feature: Decodable { let id: String }
            let features: [Feature]
        }
        struct ObsResp: Decodable {
            struct Properties: Decodable {
                struct Quant: Decodable { let value: Double? }
                let temperature: Quant?
                let windSpeed: Quant?
                let visibility: Quant?
                let textDescription: String?
                let icon: String?
            }
            let properties: Properties
        }
        struct ForecastResp: Decodable {
            struct Properties: Decodable {
                let periods: [Period]
            }
            struct Period: Decodable {
                let name: String
                let startTime: String
                let isDaytime: Bool
                let temperature: Int?
                let temperatureUnit: String?
                let probabilityOfPrecipitation: Quant?
                let shortForecast: String?
                let icon: String?
            }
            struct Quant: Decodable { let value: Double?; let unitCode: String? }
            let properties: Properties
        }

        let headers: [String: String] = [
            "User-Agent": "EusoTrip/59 (support@eusotrip.com)",
            "Accept": "application/geo+json",
        ]

        func get<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(T.self, from: data)
        }

        let pointsURL = URL(string: "https://api.weather.gov/points/\(lat),\(lon)")!
        let points = try await get(pointsURL, as: PointsResp.self)
        let stationsURL = URL(string: points.properties.observationStations)!
        let stations = try await get(stationsURL, as: StationsResp.self)
        guard let firstStation = stations.features.first else { throw URLError(.badServerResponse) }
        let obsURL = URL(string: "\(firstStation.id)/observations/latest")!
        let obs = try await get(obsURL, as: ObsResp.self)
        let p = obs.properties

        // NWS gives temperature in C, wind in km/h, visibility in m.
        let tempC = p.temperature?.value ?? .nan
        let tempF = Int((tempC * 9.0 / 5.0 + 32.0).rounded())
        let windKmh = p.windSpeed?.value ?? 0
        let windMph = Int((windKmh * 0.621371).rounded())
        let visM = p.visibility?.value ?? 0
        let visMi = Int((visM / 1609.344).rounded())
        let conditionText = p.textDescription ?? "Conditions unknown"
        let symbol = Self.nwsSymbol(for: conditionText, iconURL: p.icon)

        let cityFromPlacemark: String = {
            if let p = placemark {
                let loc = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Nearby"
                if let state = p.administrativeArea, state.count <= 3, state != loc {
                    return "\(loc), \(state)"
                }
                return loc
            }
            if let rl = points.properties.relativeLocation?.properties,
               let c = rl.city, let s = rl.state {
                return "\(c), \(s)"
            }
            return "Current location"
        }()

        // Fetch the 7-day / 14-period forecast and fold day+night
        // periods into 5 daily entries. NWS interleaves periods like
        // "Today" (day) / "Tonight" (night) / "Tuesday" (day) / "Tuesday
        // Night" / etc. — the day period carries the high, the night
        // period carries the low. Without this the card flipped to
        // "Forecast unavailable" any time WeatherKit failed and NWS
        // succeeded, because the prior NWS path only fetched current
        // observations and never populated `daily`.
        let daily: [WeatherSnapshot.DailyForecast] = await Self.fetchNWSDaily(
            forecastURL: URL(string: points.properties.forecast),
            headers: headers
        )

        // Use today's high/low for the card's `nextAlert` line so the
        // current conditions still ride with a forward-looking nudge
        // (matches the WeatherKit + Open-Meteo paths).
        let nextAlert: String? = {
            guard let today = daily.first else { return nil }
            return "today · H \(today.highF)° / L \(today.lowF)°"
        }()

        // Severity accent — promote to .warn on hazard text or low
        // visibility / strong wind, .watch on moderate condition. NWS
        // doesn't ship a numeric severity so we infer from the
        // textDescription, mirroring the Open-Meteo branch's logic.
        let accent: WeatherSnapshot.Accent = {
            let t = conditionText.lowercased()
            let severeText = t.contains("thunder") || t.contains("blizzard") ||
                             t.contains("hurricane") || t.contains("tropical") ||
                             t.contains("freezing rain") || t.contains("ice storm")
            let watchText  = t.contains("rain") || t.contains("snow") ||
                             t.contains("fog") || t.contains("haze") ||
                             t.contains("drizzle") || t.contains("flurr")
            if severeText || windMph >= 25 || visMi <= 2 { return .warn }
            if watchText { return .watch }
            return .calm
        }()

        return WeatherSnapshot(
            city: cityFromPlacemark,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visMi,
            condition: conditionText,
            symbol: symbol,
            nextAlert: nextAlert,
            accent: accent,
            daily: daily
        )
    }

    /// Fold NWS's interleaved day/night period list into 5 daily
    /// entries. Returns `[]` on any error so the surrounding NWS path
    /// still ships a usable current-observation snapshot — empty
    /// `daily` triggers the WeatherCard's neutral fallback rather than
    /// the entire fetch failing.
    private static func fetchNWSDaily(
        forecastURL: URL?,
        headers: [String: String]
    ) async -> [WeatherSnapshot.DailyForecast] {
        guard let forecastURL else { return [] }
        struct ForecastResp: Decodable {
            struct Properties: Decodable {
                let periods: [Period]
            }
            struct Period: Decodable {
                let name: String
                let startTime: String
                let isDaytime: Bool
                let temperature: Int?
                let temperatureUnit: String?
                let probabilityOfPrecipitation: Quant?
                let shortForecast: String?
                let icon: String?
            }
            struct Quant: Decodable { let value: Double?; let unitCode: String? }
            let properties: Properties
        }

        var req = URLRequest(url: forecastURL)
        req.timeoutInterval = 6
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let payload: ForecastResp
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return [] }
            payload = try JSONDecoder().decode(ForecastResp.self, from: data)
        } catch {
            return []
        }

        // ISO8601 with offset — NWS startTime examples: "2026-04-27T06:00:00-05:00"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let dayKeyFmt = DateFormatter()
        dayKeyFmt.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFmt.dateFormat = "yyyy-MM-dd"

        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = .current
        weekdayFmt.dateFormat = "EEE"

        // Bucket periods by local date, tracking which side carried the
        // day vs night reading. NWS guarantees day's temperature is the
        // high, night's is the low, but not every bucket has both
        // (today's bucket may only have a night period if it's already
        // afternoon).
        struct Acc {
            var date: Date
            var highF: Int?
            var lowF: Int?
            var symbol: String = "cloud.fill"
            var condition: String = "Mixed"
            var precipChance: Double?
        }
        var byDay: [(key: String, acc: Acc)] = []
        for p in payload.properties.periods {
            guard let date = iso.date(from: p.startTime) else { continue }
            let key = dayKeyFmt.string(from: date)
            if let idx = byDay.firstIndex(where: { $0.key == key }) {
                if p.isDaytime {
                    if let t = p.temperature { byDay[idx].acc.highF = t }
                    byDay[idx].acc.symbol    = nwsSymbol(for: p.shortForecast ?? "", iconURL: p.icon)
                    byDay[idx].acc.condition = p.shortForecast ?? byDay[idx].acc.condition
                } else {
                    if let t = p.temperature { byDay[idx].acc.lowF = t }
                }
                if let pop = p.probabilityOfPrecipitation?.value, byDay[idx].acc.precipChance == nil {
                    byDay[idx].acc.precipChance = pop / 100.0
                }
            } else {
                var acc = Acc(date: date)
                if p.isDaytime {
                    if let t = p.temperature { acc.highF = t }
                    acc.symbol    = nwsSymbol(for: p.shortForecast ?? "", iconURL: p.icon)
                    acc.condition = p.shortForecast ?? acc.condition
                } else {
                    if let t = p.temperature { acc.lowF = t }
                    acc.symbol    = nwsSymbol(for: p.shortForecast ?? "", iconURL: p.icon)
                    acc.condition = p.shortForecast ?? acc.condition
                }
                if let pop = p.probabilityOfPrecipitation?.value {
                    acc.precipChance = pop / 100.0
                }
                byDay.append((key: key, acc: acc))
            }
        }

        let cal = Calendar.current
        return byDay.prefix(5).map { entry -> WeatherSnapshot.DailyForecast in
            let high = entry.acc.highF ?? entry.acc.lowF ?? 0
            let low  = entry.acc.lowF  ?? entry.acc.highF ?? 0
            let label = cal.isDateInToday(entry.acc.date) ? "Today" : weekdayFmt.string(from: entry.acc.date)
            return WeatherSnapshot.DailyForecast(
                date: entry.acc.date,
                weekdayLabel: label,
                highF: high,
                lowF: low,
                symbol: entry.acc.symbol,
                condition: entry.acc.condition,
                precipChance: entry.acc.precipChance
            )
        }
    }

    /// Map NWS textDescription / icon URL → SF Symbol so the weather
    /// card glyph matches the dashboard's symbol vocabulary.
    private static func nwsSymbol(for text: String, iconURL: String?) -> String {
        let t = text.lowercased()
        if t.contains("thunder") { return "cloud.bolt.rain" }
        if t.contains("snow") || t.contains("flurr") { return "cloud.snow.fill" }
        if t.contains("rain") || t.contains("shower") { return "cloud.rain.fill" }
        if t.contains("drizzle") { return "cloud.drizzle.fill" }
        if t.contains("fog") || t.contains("mist") || t.contains("haze") { return "cloud.fog.fill" }
        if t.contains("cloud") || t.contains("overcast") { return "cloud.fill" }
        if t.contains("partly") || t.contains("mostly clear") { return "cloud.sun.fill" }
        if t.contains("clear") || t.contains("sunny") || t.contains("fair") { return "sun.max.fill" }
        return "cloud.fill"
    }

    // MARK: - Open-Meteo fallback (real weather, no auth)

    /// Calls https://api.open-meteo.com — a free, keyless weather API — so the
    /// dashboard still renders accurate conditions when WeatherKit is not
    /// entitled on this build. Units are requested in imperial so we don't
    /// need to convert.
    private func fetchOpenMeteo(
        location: CLLocation,
        placemark: CLPlacemark?
    ) async throws -> WeatherSnapshot {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,wind_speed_10m,weather_code"),
            URLQueryItem(name: "hourly", value: "visibility"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        // City — mirror the WeatherKit path's locality-preference order.
        let city: String = {
            if let p = placemark {
                let loc = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Nearby"
                if let state = p.administrativeArea, state.count <= 3, state != loc {
                    return "\(loc), \(state)"
                }
                return loc
            }
            // Geolocation unavailable — never leak a hardcoded city name.
            // "Current location" is the honest fallback whether the GPS
            // fix is approximate or missing entirely.
            return "Current location"
        }()

        let tempF = Int(payload.current.temperature_2m.rounded())
        let windMph = Int(payload.current.wind_speed_10m.rounded())

        // Visibility — Open-Meteo ships this on hourly (meters). Prefer the
        // current hour if the timestamps align; otherwise first available.
        let visibilityMi: Int = {
            let metersCandidate: Double? = {
                guard let times = payload.hourly?.time,
                      let values = payload.hourly?.visibility,
                      !values.isEmpty else { return nil }
                let now = Date()
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(identifier: payload.timezone ?? "UTC")
                df.dateFormat = "yyyy-MM-dd'T'HH:mm"
                if let bestIdx = times.indices.min(by: { a, b in
                    let da = df.date(from: times[a]) ?? .distantPast
                    let db = df.date(from: times[b]) ?? .distantPast
                    return abs(da.timeIntervalSince(now)) < abs(db.timeIntervalSince(now))
                }), bestIdx < values.count {
                    return values[bestIdx]
                }
                return values.first
            }()
            if let m = metersCandidate {
                return Int((m / 1609.34).rounded())
            }
            return 10
        }()

        let (condition, symbol) = Self.openMeteoCondition(for: payload.current.weather_code)

        // Next-alert line — today's H/L pulled from daily.
        let nextAlert: String? = {
            guard
                let hi = payload.daily.temperature_2m_max.first,
                let lo = payload.daily.temperature_2m_min.first
            else { return nil }
            return "today · H \(Int(hi.rounded()))° / L \(Int(lo.rounded()))°"
        }()

        // Accent — map WMO code + wind/vis thresholds to our three-level scale.
        let accent: WeatherSnapshot.Accent = {
            let code = payload.current.weather_code
            let hazardousWind = windMph >= 25
            let lowVis = visibilityMi <= 2
            let severe: Set<Int> = [65, 67, 75, 82, 86, 95, 96, 99] // heavy rain/snow, thunder
            let watch: Set<Int> = [45, 48, 51, 53, 55, 56, 57, 61, 63, 66, 71, 73, 77, 80, 81, 85]
            if severe.contains(code) || hazardousWind || lowVis { return .warn }
            if watch.contains(code) { return .watch }
            return .calm
        }()

        // Pull the 5-day daily block into driver-facing entries. The
        // weekday label is localized against the IANA timezone Open-Meteo
        // resolves for the coordinate, so drivers crossing timezones
        // during a haul still see the right day chip on each card.
        let daily: [WeatherSnapshot.DailyForecast] = Self.composeOpenMeteoDaily(
            payload: payload
        )

        // 75th firing: `approximate` is always false now — the Dallas
        // fallback was removed, so we only reach this path for the
        // driver's real resolved coordinate.
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

    /// Parse the Open-Meteo daily block into our 5-day forecast array.
    /// Safe against partial payloads — if any of the parallel daily
    /// arrays are shorter than expected we just emit the entries we
    /// can verify.
    private static func composeOpenMeteoDaily(
        payload: OpenMeteoResponse
    ) -> [WeatherSnapshot.DailyForecast] {
        let daily = payload.daily
        let count = min(
            daily.time?.count ?? 0,
            daily.temperature_2m_max.count,
            daily.temperature_2m_min.count
        )
        guard count > 0 else { return [] }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: payload.timezone ?? "UTC") ?? .current
        df.dateFormat = "yyyy-MM-dd"

        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = .current
        weekdayFmt.timeZone = TimeZone(identifier: payload.timezone ?? "UTC") ?? .current
        weekdayFmt.dateFormat = "EEE"

        let todayKey: String = {
            let now = DateFormatter()
            now.locale = Locale(identifier: "en_US_POSIX")
            now.timeZone = weekdayFmt.timeZone
            now.dateFormat = "yyyy-MM-dd"
            return now.string(from: Date())
        }()

        var out: [WeatherSnapshot.DailyForecast] = []
        for i in 0..<count {
            guard
                let times = daily.time,
                let date = df.date(from: times[i])
            else { continue }
            let key = times[i]
            let weekday = (key == todayKey) ? "Today" : weekdayFmt.string(from: date)
            let code = (daily.weather_code?.indices.contains(i) == true) ? daily.weather_code![i] : 0
            let (condition, symbol) = openMeteoCondition(for: code)
            let precip: Double? = {
                guard let arr = daily.precipitation_probability_max,
                      arr.indices.contains(i),
                      let v = arr[i] else { return nil }
                return Double(v) / 100.0
            }()
            out.append(WeatherSnapshot.DailyForecast(
                date: date,
                weekdayLabel: weekday,
                highF: Int(daily.temperature_2m_max[i].rounded()),
                lowF: Int(daily.temperature_2m_min[i].rounded()),
                symbol: symbol,
                condition: condition,
                precipChance: precip
            ))
        }
        return out
    }

    /// Translate an Open-Meteo WMO weather code to a human phrase and
    /// matching SF Symbol glyph.
    private static func openMeteoCondition(for code: Int) -> (String, String) {
        switch code {
        case 0:       return ("Clear", "sun.max")
        case 1:       return ("Mostly clear", "sun.max")
        case 2:       return ("Partly cloudy", "cloud.sun")
        case 3:       return ("Overcast", "cloud")
        case 45, 48:  return ("Fog", "cloud.fog")
        case 51:      return ("Light drizzle", "cloud.drizzle")
        case 53:      return ("Drizzle", "cloud.drizzle")
        case 55:      return ("Heavy drizzle", "cloud.drizzle.fill")
        case 56, 57:  return ("Freezing drizzle", "cloud.sleet")
        case 61:      return ("Light rain", "cloud.rain")
        case 63:      return ("Rain", "cloud.rain")
        case 65:      return ("Heavy rain", "cloud.heavyrain")
        case 66, 67:  return ("Freezing rain", "cloud.sleet.fill")
        case 71:      return ("Light snow", "cloud.snow")
        case 73:      return ("Snow", "cloud.snow")
        case 75:      return ("Heavy snow", "cloud.snow.fill")
        case 77:      return ("Snow grains", "cloud.snow")
        case 80:      return ("Rain showers", "cloud.rain")
        case 81:      return ("Rain showers", "cloud.rain")
        case 82:      return ("Violent showers", "cloud.heavyrain.fill")
        case 85, 86:  return ("Snow showers", "cloud.snow")
        case 95:      return ("Thunderstorm", "cloud.bolt.rain")
        case 96, 99:  return ("Thunder + hail", "cloud.bolt.rain.fill")
        default:      return ("Cloudy", "cloud")
        }
    }

    // MARK: - Open-Meteo wire types

    private struct OpenMeteoResponse: Decodable {
        let timezone: String?
        let current: Current
        let hourly: Hourly?
        let daily: Daily

        struct Current: Decodable {
            let temperature_2m: Double
            let wind_speed_10m: Double
            let weather_code: Int
        }
        struct Hourly: Decodable {
            let time: [String]
            let visibility: [Double]
        }
        struct Daily: Decodable {
            let time: [String]?
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let weather_code: [Int]?
            let precipitation_probability_max: [Int?]?
        }
    }

    // MARK: - Composition

    private static func compose(
        weather: Weather,
        placemark: CLPlacemark?
    ) -> WeatherSnapshot {
        let current = weather.currentWeather

        // City string — prefer locality, fall back to subAdministrativeArea,
        // and append the state short-code where available ("Meridian, MS").
        let city: String = {
            if let p = placemark {
                let loc = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Nearby"
                if let state = p.administrativeArea, state.count <= 3, state != loc {
                    return "\(loc), \(state)"
                }
                return loc
            }
            return "Current location"
        }()

        // Temperature in Fahrenheit (rounded).
        let tempF = Int(current.temperature.converted(to: .fahrenheit).value.rounded())

        // Wind in mph.
        let windMph = Int(current.wind.speed.converted(to: .milesPerHour).value.rounded())

        // Visibility in whole miles.
        let visibilityMi = Int(current.visibility.converted(to: .miles).value.rounded())

        // Condition line + matching SF Symbol.
        let condition = current.condition.description
        let symbol = current.symbolName

        // Next-alert line — scan the next 6 hours for the first forecast entry
        // whose condition is materially different from now, and format as
        // "Nh · <condition>". If nothing changes, use the day's summary.
        let nextAlert: String = {
            let nowCondition = current.condition
            let horizon = weather.hourlyForecast.forecast.prefix(6)
            for (i, hour) in horizon.enumerated() where hour.condition != nowCondition {
                let offset = i + 1
                return "\(offset)h · \(hour.condition.description.lowercased())"
            }
            if let today = weather.dailyForecast.first {
                let hi = Int(today.highTemperature.converted(to: .fahrenheit).value.rounded())
                let lo = Int(today.lowTemperature.converted(to: .fahrenheit).value.rounded())
                return "today · H \(hi)° / L \(lo)°"
            }
            return nil as String? ?? ""
        }()

        // Accent — map WeatherKit severity to our three-level scale.
        let accent: WeatherSnapshot.Accent = {
            if weather.weatherAlerts?.contains(where: { $0.severity == .severe || $0.severity == .extreme }) == true {
                return .warn
            }
            let hazardousWind = windMph >= 25
            let lowVis = visibilityMi <= 2
            let hazardCondition: Bool = {
                switch current.condition {
                case .thunderstorms, .heavyRain, .heavySnow, .blizzard,
                        .hurricane, .tropicalStorm, .strongStorms,
                        .freezingRain, .freezingDrizzle, .hail, .sleet, .wintryMix:
                    return true
                default:
                    return false
                }
            }()
            if hazardousWind || lowVis || hazardCondition { return .warn }

            let watchCondition: Bool = {
                switch current.condition {
                case .rain, .drizzle, .snow, .flurries, .sunShowers,
                        .foggy, .haze, .smoky, .blowingDust, .blowingSnow,
                        .scatteredThunderstorms, .isolatedThunderstorms:
                    return true
                default:
                    return false
                }
            }()
            if watchCondition { return .watch }
            return .calm
        }()

        // Pull the first 5 days of the WeatherKit daily forecast into
        // the flip-side array. We cap at 5 because the card has fixed
        // vertical real-estate and more rows forces each row to shrink
        // below the legibility threshold on a 6.1" iPhone.
        let daily: [WeatherSnapshot.DailyForecast] = {
            let weekdayFmt = DateFormatter()
            weekdayFmt.locale = .current
            weekdayFmt.dateFormat = "EEE"
            let cal = Calendar.current

            return weather.dailyForecast.forecast.prefix(5).enumerated().map { (i, day) in
                let hi = Int(day.highTemperature.converted(to: .fahrenheit).value.rounded())
                let lo = Int(day.lowTemperature.converted(to: .fahrenheit).value.rounded())
                let label: String = {
                    if cal.isDateInToday(day.date) { return "Today" }
                    if i == 0 { return "Today" }
                    return weekdayFmt.string(from: day.date)
                }()
                return WeatherSnapshot.DailyForecast(
                    date: day.date,
                    weekdayLabel: label,
                    highF: hi,
                    lowF: lo,
                    symbol: day.symbolName,
                    condition: day.condition.description,
                    precipChance: day.precipitationChance
                )
            }
        }()

        return WeatherSnapshot(
            city: city,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visibilityMi,
            condition: condition,
            symbol: symbol,
            nextAlert: nextAlert.isEmpty ? nil : nextAlert,
            accent: accent,
            daily: daily
        )
    }

    // MARK: - Location (one-shot)

    private func requestLocationIfNeeded() async -> CLLocation? {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Wait for the permission prompt to resolve (user action can
            // take any amount of time — poll for up to 8 seconds).
            for _ in 0..<16 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if locationManager.authorizationStatus != .notDetermined { break }
            }
            if locationManager.authorizationStatus == .authorizedWhenInUse
                || locationManager.authorizationStatus == .authorizedAlways {
                return await requestLocationOneShot()
            }
            return nil
        case .authorizedWhenInUse, .authorizedAlways:
            return await requestLocationOneShot()
        case .denied, .restricted:
            return nil
        @unknown default:
            return nil
        }
    }

    /// One-shot location read with a 4-second hard timeout so the
    /// simulator (which often has no GPS fix at all) can't stall us.
    private func requestLocationOneShot() async -> CLLocation? {
        await withTaskGroup(of: CLLocation?.self, returning: CLLocation?.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
                    self.pendingLocation = cont
                    self.locationManager.requestLocation()
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Reverse geocode

    private func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark? {
        try await CLGeocoder().reverseGeocodeLocation(location).first
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Pick the freshest fix that's also recent enough to trust.
        // Without this filter CoreLocation occasionally hands us a
        // multi-day-old cached fix from a previous region, which is
        // why weather rendered last week's storm system over a town
        // the driver had already left. The maxAge gate is read from
        // the actor's stored value via a Task hop so the rest of the
        // delegate stays nonisolated.
        let snapshot = locations.last
        Task { @MainActor in
            let now = Date()
            let acceptable: CLLocation? = {
                guard let s = snapshot else { return nil }
                return abs(now.timeIntervalSince(s.timestamp)) <= self.maxLocationAgeSeconds ? s : nil
            }()
            self.pendingLocation?.resume(returning: acceptable)
            self.pendingLocation = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.pendingLocation?.resume(returning: nil)
            self.pendingLocation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        // No-op: the one-shot path re-checks authorizationStatus itself.
    }
}
