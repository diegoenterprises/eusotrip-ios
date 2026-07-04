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
    /// Was 60s — too tight: CoreLocation's first response on a fresh
    /// app launch is frequently a cached fix older than 60s, which
    /// got silently rejected and the weather widget never rendered
    /// for either persona (founder report 2026-05-05 — "home screen
    /// weather widget didn't load … for either user"). 600s (10 min)
    /// is the sweet spot — drivers stay inside the same weather cell
    /// for that long unless on a sustained haul, and the next
    /// `requestLocation()` we issue refreshes the fix anyway.
    private let maxLocationAgeSeconds: TimeInterval = 600

    private let weatherService = WeatherKit.WeatherService.shared

    private var pendingLocation: CheckedContinuation<CLLocation?, Never>?
    private var pendingLocationID: UUID?

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

    /// Fire the iOS "Allow EusoTrip to use your location?" prompt
    /// directly. Idempotent: if status is already determined (granted,
    /// denied, or restricted), this is a no-op. Callers use it to
    /// surface the system dialog from a CTA tap when the previous
    /// "request on first weather fetch" path didn't fire (e.g.
    /// because the home view appeared before `fetchCurrent()`'s
    /// internal `requestWhenInUseAuthorization()` reached the runloop).
    /// Founder report 2026-05-05 — "the app doesn't ask for my
    /// location so it doesn't load the weather widget".
    func requestPermissionIfNeeded() {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Public

    /// Fetch a single current snapshot for the user's present location.
    /// Returns `nil` on any failure — UI keeps the last real reading when
    /// one exists, or shows an honest permission/unavailable state.
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
    /// In-memory last-good snapshot, seeded on every successful fetch. A
    /// returning view (navigation back, app foreground) renders the weather
    /// INSTANTLY from this instead of flashing a loading skeleton while the
    /// live fetch runs. Not a fabrication — it's the most recent REAL
    /// reading, and it's only ever replaced by a newer real one.
    static private(set) var lastSnapshot: WeatherSnapshot? = loadCachedSnapshot()

    /// The cached last-good snapshot, if any. Consumers show it immediately
    /// and refresh in the background.
    static var cachedSnapshot: WeatherSnapshot? {
        guard let snap = lastSnapshot, isUsableCachedSnapshot(snap) else {
            lastSnapshot = loadCachedSnapshot()
            return lastSnapshot
        }
        return snap
    }

    /// Public entry point — fetches a fresh snapshot and updates the
    /// last-good cache. Returns nil on failure; the caller keeps showing
    /// the cache / an honest empty state rather than a blank/stuck card.
    func fetchCurrent() async -> WeatherSnapshot? {
        let snap = await fetchCurrentUncached()
        if let snap { Self.storeLastSnapshot(snap) }
        return snap
    }

    private static let cachedSnapshotMaxAge: TimeInterval = 90 * 60
    private static let cachedSnapshotFileName = "WeatherSnapshot.last-real.json"

    private static func storeLastSnapshot(_ snapshot: WeatherSnapshot) {
        lastSnapshot = snapshot
        persistCachedSnapshot(snapshot)
    }

    private static func isUsableCachedSnapshot(_ snapshot: WeatherSnapshot) -> Bool {
        guard let observedAt = snapshot.observedAt else { return false }
        return Date().timeIntervalSince(observedAt) <= cachedSnapshotMaxAge
    }

    private static func cacheURL() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches
            .appendingPathComponent("EusoTrip", isDirectory: true)
            .appendingPathComponent(cachedSnapshotFileName)
    }

    private static func loadCachedSnapshot() -> WeatherSnapshot? {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WeatherSnapshot.self, from: data),
              isUsableCachedSnapshot(snapshot) else { return nil }
        return snapshot
    }

    private static func persistCachedSnapshot(_ snapshot: WeatherSnapshot) {
        guard let url = cacheURL() else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[WeatherService] Could not persist last real weather snapshot — \(error.localizedDescription)")
        }
    }

    private func fetchCurrentUncached() async -> WeatherSnapshot? {
        guard let location = await requestLocationIfNeeded() else {
            return nil
        }

        // ── Apple WeatherKit (on-device) is the PRIMARY source ──
        //
        // The carrier `weatherCode` the v2 glyph set needs is produced
        // on-device from the WeatherKit condition (see `compose`), and the
        // server procs (weather.realtime / timelines / forLoad) are now
        // WeatherKit-backed too — so the home card and the lane-impact
        // card share one honest provider. No weather API key ever ships in
        // the iOS bundle; on-device WeatherKit uses the app entitlement,
        // the server uses its own JWT. On any miss we fall through to
        // NWS → Open-Meteo — NEVER a fabricated reading.
        // PRIMARY: the server (weather.byLatLon) is WeatherKit-backed
        // server-side (PR #101), so it reliably carries current + hourly +
        // the 7-DAY daily strip and is attributed as Apple Weather. The key
        // lives ONLY in the server env, never the bundle. We prefer it
        // because on-device WeatherKit needs the App ID capability enabled;
        // until then it throws (codes 2/3/4/7) and we'd lose the daily strip
        // (the regression that emptied the 7-day chips). On any server miss
        // we fall through to on-device WeatherKit → NWS → Open-Meteo — NEVER
        // a fabricated reading.
        let placemark = try? await reverseGeocode(location)
        if let server = await fetchServerWeather(location: location, placemark: placemark) {
            return server
        }
        do {
            let weather = try await weatherService.weather(for: location)
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

    // MARK: - Server weather (WeatherKit-backed, server-proxied)

    // Wire types for the tRPC `weather.byLatLon` proc (WeatherKit-backed
    // current + hourly + 7-day daily + the single alert). All fields are
    // optional so a partial/honest server payload (missing key → "no
    // data") decodes cleanly and the client falls back rather than
    // synthesising. Field names mirror the server's normalised shape.
    private struct ServerWeather: Decodable {
        // byLatLon emits { source, fetchedAt, weatherCode, current{}, hourly[],
        // daily[], alerts[] } in the canonical METRIC NormalizedWeather shape
        // (°C / km/h / km) — the SAME shape the web Weather.tsx reads. We
        // convert to imperial in the mapping below.
        let source: String?
        let fetchedAt: String?
        let weatherCode: Int?
        let current: Current?
        let hourly: [Hour]?
        let daily: [Day]?
        let alerts: [Alert]?
        let nextHour: NextHour?

        struct Current: Decodable {
            let tempC: Double?
            let feelsC: Double?
            let condition: String?
            let icon: String?
            let uv: Double?
            let windKph: Double?
            let humidity: Double?
            let weatherCode: Int?
            let visibilityKm: Double?
            let windGustKph: Double?
            let precipPct: Double?
        }
        struct Hour: Decodable {
            let t: String?
            let tempC: Double?
            let precipPct: Double?
            let condition: String?
            let weatherCode: Int?
            let windKph: Double?
            let windGustKph: Double?
            let visibilityKm: Double?
            let uv: Double?
            let precipMm: Double?
            let precipType: String?
        }
        struct Day: Decodable {
            let d: String?
            let hi: Double?
            let lo: Double?
            let condition: String?
            let precipPct: Double?
            let sunrise: String?
            let sunset: String?
            let weatherCode: Int?
        }
        struct Alert: Decodable {
            let title: String?
            let severity: String?
            let start: String?
            let end: String?
            let description: String?
            let area: String?
        }
        struct NextHour: Decodable {
            let forecastStart: String?
            let forecastEnd: String?
            let minutes: [Minute]?
            let summary: [Summary]?

            struct Minute: Decodable {
                let t: String?
                let precipPct: Double?
                let precipIntensityMmPerHour: Double?
            }
            struct Summary: Decodable {
                let start: String?
                let end: String?
                let precipPct: Double?
                let precipIntensityMmPerHour: Double?
                let precipitationType: String?
            }
        }
    }

    private struct ByLatLonInput: Encodable {
        let lat: Double
        let lon: Double
        let units: String
        let preferredSource: String
    }

    /// Fetch the WeatherKit-backed snapshot via the tRPC proxy. Returns
    /// `nil` on ANY failure (server unreachable, key absent → server
    /// returns no data, decode error) so `fetchCurrent()` falls through
    /// to the WeatherKit/NWS/Open-Meteo chain. Never fabricates: a nil
    /// `tempF` from the server (no data) yields `nil` here, not a zero.
    private func fetchServerWeather(
        location: CLLocation,
        placemark: CLPlacemark?
    ) async -> WeatherSnapshot? {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude

        let server: ServerWeather
        do {
            server = try await EusoTripAPI.shared.query(
                "weather.byLatLon",
                input: ByLatLonInput(
                    lat: lat,
                    lon: lng,
                    units: "imperial",
                    preferredSource: "weatherkit"
                )
            )
        } catch {
            // Server down, proc not deployed yet, or key-absent →
            // "no data". Honest fall-through, not a fabricated card.
            print("[WeatherService] weather.byLatLon unavailable — \(error.localizedDescription)")
            return nil
        }

        // Require a real current temperature + condition. Without these
        // the server had no Tomorrow.io data (key absent / upstream
        // failure) and we MUST fall back rather than render an empty
        // shell that looks live.
        guard let cur = server.current,
              let tC = cur.tempC else {
            return nil
        }
        let code = cur.weatherCode ?? Self.serverWeatherCode(condition: cur.condition, icon: cur.icon)
        // byLatLon is metric (the web reads the same shape) → convert here.
        func cToF(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }
        func kphToMph(_ k: Double) -> Double { k * 0.621371 }
        func kmToMi(_ k: Double) -> Double { k * 0.621371 }
        let tF = cToF(tC)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }

        let condition = cur.condition ?? Self.tomorrowCondition(for: code)

        // City — prefer the reverse-geocoded placemark (matches the rest
        // of the pipeline), else the server's, else honest fallback.
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

        let hourly: [WeatherSnapshot.HourlyForecast] = (server.hourly ?? []).prefix(8).compactMap { h in
            guard let date = parseDate(h.t), let t = h.tempC else { return nil }
            let hourCode = h.weatherCode ?? Self.serverWeatherCode(condition: h.condition, icon: nil)
            return WeatherSnapshot.HourlyForecast(
                date: date,
                tempF: Int(cToF(t).rounded()),
                symbol: Self.tomorrowSymbol(for: hourCode),
                precipChancePct: h.precipPct.map { Int($0.rounded()) },
                windMph: h.windKph.map { Int(kphToMph($0).rounded()) },
                weatherCode: hourCode
            )
        }

        let nextHourPrecip: WeatherSnapshot.NextHourPrecip? = {
            guard let next = server.nextHour else { return nil }
            let minutes = (next.minutes ?? []).compactMap { minute -> WeatherSnapshot.NextHourPrecip.Minute? in
                guard let date = parseDate(minute.t) else { return nil }
                return WeatherSnapshot.NextHourPrecip.Minute(
                    date: date,
                    precipChancePct: minute.precipPct.map { Int($0.rounded()) },
                    intensityMmPerHour: minute.precipIntensityMmPerHour
                )
            }
            let summaries = (next.summary ?? []).compactMap { summary -> WeatherSnapshot.NextHourPrecip.Summary? in
                guard let start = parseDate(summary.start) else { return nil }
                return WeatherSnapshot.NextHourPrecip.Summary(
                    start: start,
                    end: parseDate(summary.end),
                    precipChancePct: summary.precipPct.map { Int($0.rounded()) },
                    intensityMmPerHour: summary.precipIntensityMmPerHour,
                    precipitationType: summary.precipitationType
                )
            }
            guard !minutes.isEmpty || !summaries.isEmpty else { return nil }
            return WeatherSnapshot.NextHourPrecip(
                forecastStart: parseDate(next.forecastStart),
                forecastEnd: parseDate(next.forecastEnd),
                minutes: minutes,
                summaries: summaries
            )
        }()

        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = .current
        weekdayFmt.dateFormat = "EEE"
        let cal = Calendar.current
        let daily: [WeatherSnapshot.DailyForecast] = (server.daily ?? []).prefix(7).compactMap { d in
            guard let date = parseDate(d.d) ?? Self.dayOnly(d.d),
                  let hi = d.hi, let lo = d.lo else { return nil }
            let label = cal.isDateInToday(date) ? "Today" : weekdayFmt.string(from: date)
            let dayCode = d.weatherCode ?? Self.serverWeatherCode(condition: d.condition, icon: nil)
            return WeatherSnapshot.DailyForecast(
                date: date,
                weekdayLabel: label,
                highF: Int(cToF(hi).rounded()),
                lowF: Int(cToF(lo).rounded()),
                symbol: Self.tomorrowSymbol(for: dayCode),
                condition: d.condition ?? Self.tomorrowCondition(for: dayCode),
                precipChance: d.precipPct.map { $0 / 100.0 }
            )
        }

        let alert: WeatherSnapshot.ActiveAlert? = (server.alerts ?? []).first.flatMap { a in
            guard let title = a.title, !title.isEmpty else { return nil }
            return WeatherSnapshot.ActiveAlert(
                title: title,
                severity: WeatherSnapshot.AlertSeverity(capString: a.severity),
                until: parseDate(a.end)
            )
        }

        let windMph = Int(kphToMph(cur.windKph ?? 0).rounded())
        let visMi = Int((cur.visibilityKm.map(kmToMi) ?? 10).rounded())

        // Accent — real alert severity wins, else freight thresholds +
        // the code family, mirroring the other paths.
        let accent: WeatherSnapshot.Accent = {
            if let sev = alert?.severity, sev >= .severe { return .warn }
            let severeCodes: Set<Int> = [8000, 4201, 6201, 7101]
            let watchCodes: Set<Int> = [4000, 4200, 4001, 5000, 5001, 5100, 5101,
                                        6000, 6001, 6200, 7000, 7102, 2000, 2100]
            if severeCodes.contains(code) || windMph >= 25 || visMi <= 2 { return .warn }
            if alert != nil { return .watch }
            if watchCodes.contains(code) { return .watch }
            return .calm
        }()

        let nextAlert: String? = daily.first.map { "today · H \($0.highF)° / L \($0.lowF)°" }

        var snap = WeatherSnapshot(
            city: city,
            tempF: Int(tF.rounded()),
            windMph: windMph,
            visibilityMi: visMi,
            condition: condition,
            symbol: Self.tomorrowSymbol(for: code),
            nextAlert: nextAlert,
            accent: accent,
            daily: daily,
            feelsLikeF: cur.feelsC.map { Int(cToF($0).rounded()) },
            humidityPct: cur.humidity.map { Int($0.rounded()) },
            windGustMph: cur.windGustKph.map { Int(kphToMph($0).rounded()) },
            precipChancePct: cur.precipPct.map { Int($0.rounded()) }
                ?? nextHourPrecip?.peakMinute?.precipChancePct,
            nextHourPrecip: nextHourPrecip,
            hourly: hourly
        )
        snap.weatherCode = code
        // Honest provenance from the server's own source tag. byLatLon is
        // WeatherKit-backed now (PR #101); credit Apple Weather, never a
        // retired provider.
        switch (server.source ?? "").lowercased() {
        case "weatherkit":               snap.dataSource = .weatherKit
        case "openweather", "openmeteo": snap.dataSource = .openMeteo
        case "nws":                      snap.dataSource = .nws
        default:                         snap.dataSource = .weatherKit
        }
        snap.uvIndex = cur.uv.map { Int($0.rounded()) }
        snap.alert = alert
        snap.observedAt = parseDate(server.fetchedAt) ?? Date()

        // Lane impact — best-effort; its own proc, never blocks the card.
        snap.laneImpact = await fetchLaneImpact()
        return snap
    }

    // Wire types for the tRPC `weather.laneImpact` proc — per-load ETA
    // risk from Tomorrow.io /v4/route (time-aware). Optional throughout
    // so a partial/honest payload decodes; nil/empty → the panel hides.
    private struct ServerLaneImpact: Decodable {
        let available: Bool?
        let loads: [ServerSegment]?
        struct ServerSegment: Decodable {
            let loadId: String?
            let mode: String?
            let route: String?
            let pickupTime: String?
            let etaDelayMin: Int?
            let riskTier: String?
            // §3 structured peakLeg { label, time } | null. Legacy
            // payloads sent `peakLeg` as a flat string; the custom
            // decoder below accepts either the object or the string form.
            let peakLeg: ServerPeakLeg?
            // §3 headline + drivers[] + recommendation{} + computedAt.
            let headline: String?
            let drivers: [ServerDriver]?
            let recommendation: ServerRecommendation?
            let computedAt: String?
            // Legacy flat ESang line (older payloads).
            let esangSuggestion: String?

            struct ServerPeakLeg: Decodable {
                let label: String?
                let time: String?

                /// Accept `peakLeg` as either `{ label, time }` (§3) or a
                /// bare string ("4 PM storm cell on I-35", legacy) so a
                /// mixed-vintage server still decodes. A string becomes
                /// the `label`; the `time` stays nil and the diagram reads
                /// the riskTier for band placement.
                init(from decoder: Decoder) throws {
                    if let single = try? decoder.singleValueContainer(),
                       let s = try? single.decode(String.self) {
                        self.label = s
                        self.time = nil
                        return
                    }
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    self.label = try c.decodeIfPresent(String.self, forKey: .label)
                    self.time  = try c.decodeIfPresent(String.self, forKey: .time)
                }
                enum CodingKeys: String, CodingKey { case label, time }
            }
            struct ServerDriver: Decodable {
                let field: String?
                let value: String?
            }
            struct ServerRecommendation: Decodable {
                let text: String?
                let action: String?
                let protects: String?
            }
        }
    }

    /// Fetch the active loads' weather-driven ETA risk. Returns `nil` on
    /// any failure (proc absent, no active loads, route tier absent) so
    /// the LANE IMPACT panel simply collapses — never seeded.
    private struct LaneImpactActiveInput: Encodable { let limit: Int }

    private func fetchLaneImpact() async -> [WeatherSnapshot.LaneImpactSegment]? {
        let resp: ServerLaneImpact
        do {
            // laneImpactActive → the caller's active loads, each a §3 LaneImpact
            // object: { available, loads:[ { loadId, mode, riskTier, headline,
            // peakLeg{label,time}, drivers[], recommendation{}, computedAt } ] }.
            // (The single-load weather.laneImpact proc requires {loadId}; the
            // home widget wants the active set, not one load.)
            resp = try await EusoTripAPI.shared.query(
                "weather.laneImpactActive",
                input: LaneImpactActiveInput(limit: 8)
            )
        } catch {
            return nil
        }
        guard resp.available != false, let segs = resp.loads, !segs.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        let mapped: [WeatherSnapshot.LaneImpactSegment] = segs.compactMap { s in
            guard let loadId = s.loadId, !loadId.isEmpty else { return nil }
            let mode: WeatherSnapshot.LaneMode = {
                switch (s.mode ?? "").lowercased() {
                case "rail":   return .rail
                case "vessel": return .vessel
                default:       return .truck
                }
            }()
            let risk: WeatherSnapshot.RiskTier = {
                switch (s.riskTier ?? "").lowercased() {
                case "severe":         return .severe
                case "elevated":       return .elevated
                case "watch":          return .watch
                default:               return .none   // "none" / "clear" / absent
                }
            }()
            let pickup = s.pickupTime.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
            let computed = s.computedAt.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }

            // §3 peakLeg { label, time } — only built when a real label
            // came back; never synthesised. A legacy string-only payload
            // yields a label with no time.
            let peakLeg: WeatherSnapshot.PeakLeg? = {
                guard let pl = s.peakLeg,
                      let label = pl.label?.trimmingCharacters(in: .whitespaces),
                      !label.isEmpty else { return nil }
                return WeatherSnapshot.PeakLeg(label: label, time: pl.time ?? "")
            }()

            // §3 drivers[] — the mode metric tiles. Each row needs both a
            // field key and a value; honest "—" values stay (the server
            // already passes the em-dash when Tomorrow.io omitted the
            // field), but a row with no field is dropped.
            let drivers: [WeatherSnapshot.Driver] = (s.drivers ?? []).compactMap { d in
                guard let field = d.field?.trimmingCharacters(in: .whitespaces),
                      !field.isEmpty else { return nil }
                let value = (d.value?.trimmingCharacters(in: .whitespaces)).flatMap {
                    $0.isEmpty ? nil : $0
                } ?? "—"
                return WeatherSnapshot.Driver(field: field, value: value)
            }

            // §3 recommendation { text, action, protects } — only when
            // the server authored a real action; nil collapses the orb.
            let recommendation: WeatherSnapshot.Recommendation? = {
                guard let r = s.recommendation,
                      let action = r.action?.trimmingCharacters(in: .whitespaces),
                      !action.isEmpty else { return nil }
                return WeatherSnapshot.Recommendation(
                    text: r.text ?? "",
                    action: action,
                    protects: r.protects ?? ""
                )
            }()

            return WeatherSnapshot.LaneImpactSegment(
                loadId: loadId,
                mode: mode,
                riskTier: risk,
                headline: s.headline ?? "",
                peakLeg: peakLeg,
                drivers: drivers,
                recommendation: recommendation,
                computedAt: computed,
                route: s.route ?? "",
                pickupTime: pickup,
                etaDelayMin: s.etaDelayMin,
                esangSuggestion: s.esangSuggestion
            )
        }
        return mapped.isEmpty ? nil : mapped
    }

    /// Tomorrow.io weatherCode → human phrase (mirrors the wiring map's
    /// "label" column). Used when the server omits a condition string.
    private static func tomorrowCondition(for code: Int) -> String {
        switch code {
        case 1000: return "Clear"
        case 1100: return "Mostly clear"
        case 1101: return "Partly cloudy"
        case 1102: return "Mostly cloudy"
        case 1001: return "Cloudy"
        case 2000: return "Fog"
        case 2100: return "Light fog"
        case 4000: return "Drizzle"
        case 4200: return "Light rain"
        case 4001: return "Rain"
        case 4201: return "Heavy rain"
        case 8000: return "Thunderstorm"
        case 5000: return "Snow"
        case 5001: return "Flurries"
        case 5100: return "Light snow"
        case 5101: return "Heavy snow"
        case 6000: return "Freezing drizzle"
        case 6001: return "Freezing rain"
        case 6200: return "Light freezing rain"
        case 6201: return "Heavy freezing rain"
        case 7000: return "Ice pellets"
        case 7101: return "Heavy ice pellets"
        case 7102: return "Light ice pellets"
        default:   return "Cloudy"
        }
    }

    /// Tomorrow.io weatherCode → SF Symbol (kept for the legacy compact
    /// path + accessibility; the v2 surface draws WeatherIcons off the
    /// code directly).
    private static func tomorrowSymbol(for code: Int) -> String {
        switch code {
        case 1000:                         return "sun.max.fill"
        case 1100, 1101:                   return "cloud.sun.fill"
        case 1102, 1001:                   return "cloud.fill"
        case 2000, 2100:                   return "cloud.fog.fill"
        case 4000, 4200:                   return "cloud.drizzle.fill"
        case 4001:                         return "cloud.rain.fill"
        case 4201:                         return "cloud.heavyrain.fill"
        case 8000:                         return "cloud.bolt.rain.fill"
        case 5000, 5001, 5100, 5101:       return "cloud.snow.fill"
        case 6000, 6001, 6200, 6201,
             7000, 7101, 7102:             return "cloud.sleet.fill"
        default:                           return "cloud.fill"
        }
    }

    /// Server WeatherKit/OpenWeather fallback paths may not carry a
    /// Tomorrow.io numeric weatherCode. Derive the closest glyph code
    /// from the live provider condition/icon so the client keeps the
    /// payload instead of discarding a valid Apple Weather response.
    private static func serverWeatherCode(condition: String?, icon: String?) -> Int {
        let text = [condition, icon]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if text.contains("thunder") || text.contains("bolt") { return 8000 }
        if text.contains("freezing") || text.contains("sleet") || text.contains("hail") || text.contains("ice") { return 6200 }
        if text.contains("heavy") && text.contains("snow") { return 5101 }
        if text.contains("snow") || text.contains("flurr") { return 5000 }
        if text.contains("heavy") && text.contains("rain") { return 4201 }
        if text.contains("drizzle") { return 4000 }
        if text.contains("rain") || text.contains("shower") { return 4001 }
        if text.contains("fog") || text.contains("mist") || text.contains("haze") { return 2000 }
        if text.contains("partly") { return 1101 }
        if text.contains("mostly") && text.contains("clear") { return 1100 }
        if text.contains("mostly") && text.contains("cloud") { return 1102 }
        if text.contains("cloud") || text.contains("overcast") { return 1001 }
        if text.contains("clear") || text.contains("sun") { return 1000 }
        return 0
    }

    /// Parse a "yyyy-MM-dd" day string (Tomorrow.io daily timestamps can
    /// arrive date-only) to local midnight.
    private static func dayOnly(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
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
                let forecastHourly: String?
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
                let windGust: Quant?
                let visibility: Quant?
                let relativeHumidity: Quant?
                let heatIndex: Quant?
                let windChill: Quant?
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

        // Level-100 depth — humidity straight off the station; feels-like
        // from heatIndex (warm) or windChill (cold) when the station
        // reports one; gust converted km/h → mph. All nil-safe: a station
        // that omits the field yields nil and the card renders "—".
        let humidityPct: Int? = p.relativeHumidity?.value.map { Int($0.rounded()) }
        let feelsLikeF: Int? = {
            if let hi = p.heatIndex?.value { return Int((hi * 9.0 / 5.0 + 32.0).rounded()) }
            if let wc = p.windChill?.value { return Int((wc * 9.0 / 5.0 + 32.0).rounded()) }
            return nil
        }()
        let windGustMph: Int? = p.windGust?.value.map { Int(($0 * 0.621371).rounded()) }

        // Hourly band + active CAP alerts — both real NWS feeds; each
        // degrades to empty on failure without sinking the snapshot.
        async let hourlyTask = Self.fetchNWSHourly(
            hourlyURL: points.properties.forecastHourly.flatMap(URL.init(string:)),
            headers: headers
        )
        async let alertsTask = Self.fetchNWSAlerts(lat: lat, lon: lon, headers: headers)
        let hourly = await hourlyTask
        let alerts = await alertsTask
        let precipChancePct: Int? = hourly.first?.precipChancePct

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
        // periods into 6 daily entries. NWS interleaves periods like
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

        // Severity accent — real CAP severity wins; otherwise promote to
        // .warn on hazard text or low visibility / strong wind, .watch on
        // moderate condition (inferred from textDescription, mirroring
        // the Open-Meteo branch's logic).
        let accent: WeatherSnapshot.Accent = {
            if alerts.contains(where: { $0.severity >= .severe }) { return .warn }
            let t = conditionText.lowercased()
            let severeText = t.contains("thunder") || t.contains("blizzard") ||
                             t.contains("hurricane") || t.contains("tropical") ||
                             t.contains("freezing rain") || t.contains("ice storm")
            let watchText  = t.contains("rain") || t.contains("snow") ||
                             t.contains("fog") || t.contains("haze") ||
                             t.contains("drizzle") || t.contains("flurr")
            if severeText || windMph >= 25 || visMi <= 2 { return .warn }
            if watchText || alerts.contains(where: { $0.severity == .moderate }) { return .watch }
            return .calm
        }()

        var snap = WeatherSnapshot(
            city: cityFromPlacemark,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visMi,
            condition: conditionText,
            symbol: symbol,
            nextAlert: nextAlert,
            accent: accent,
            daily: daily,
            feelsLikeF: feelsLikeF,
            humidityPct: humidityPct,
            windGustMph: windGustMph,
            precipChancePct: precipChancePct,
            hourly: hourly,
            alerts: alerts
        )
        // v2: name the real provider (NWS, NOT Tomorrow.io) + infer a
        // weatherCode from the symbol so the custom glyph still lights.
        snap.dataSource = .nws
        snap.weatherCode = WeatherIcons.code(forSymbol: symbol)
        snap.observedAt = Date()
        if let top = alerts.max(by: { $0.severity.rank < $1.severity.rank }) {
            snap.alert = .init(title: top.event, severity: top.severity, until: top.endsAt)
        }
        return snap
    }

    /// Next-12-hours band from NWS `forecastHourly`. Returns `[]` on
    /// any failure so the snapshot still ships without an hourly band
    /// (the card collapses the strip — no fabricated hours).
    private static func fetchNWSHourly(
        hourlyURL: URL?,
        headers: [String: String]
    ) async -> [WeatherSnapshot.HourlyForecast] {
        guard let hourlyURL else { return [] }
        struct HourlyResp: Decodable {
            struct Properties: Decodable { let periods: [Period] }
            struct Period: Decodable {
                let startTime: String
                let temperature: Int?
                let temperatureUnit: String?
                let probabilityOfPrecipitation: Quant?
                let windSpeed: String?
                let shortForecast: String?
                let icon: String?
            }
            struct Quant: Decodable { let value: Double? }
            let properties: Properties
        }

        var req = URLRequest(url: hourlyURL)
        req.timeoutInterval = 6
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let payload = try? JSONDecoder().decode(HourlyResp.self, from: data)
        else { return [] }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let cutoff = Date().addingTimeInterval(-1800)

        return payload.properties.periods
            .compactMap { p -> WeatherSnapshot.HourlyForecast? in
                guard
                    let date = iso.date(from: p.startTime),
                    date >= cutoff,
                    let t = p.temperature
                else { return nil }
                // NWS hourly windSpeed arrives as a display string
                // ("10 mph") — parse the leading integer; nil when absent.
                let wind: Int? = p.windSpeed
                    .flatMap { $0.split(separator: " ").first }
                    .flatMap { Int($0) }
                let tempF = (p.temperatureUnit ?? "F").uppercased() == "C"
                    ? Int((Double(t) * 9.0 / 5.0 + 32.0).rounded())
                    : t
                return WeatherSnapshot.HourlyForecast(
                    date: date,
                    tempF: tempF,
                    symbol: nwsSymbol(for: p.shortForecast ?? "", iconURL: p.icon),
                    precipChancePct: p.probabilityOfPrecipitation?.value.map { Int($0.rounded()) },
                    windMph: wind
                )
            }
            .prefix(12)
            .map { $0 }
    }

    /// Active CAP bulletins for the point from api.weather.gov/alerts.
    /// Real NWS severity vocabulary — Minor/Moderate/Severe/Extreme.
    /// Returns `[]` on failure (no alerts ≠ fabricated calm; the card
    /// simply shows no ribbon).
    private static func fetchNWSAlerts(
        lat: Double,
        lon: Double,
        headers: [String: String]
    ) async -> [WeatherSnapshot.SevereAlert] {
        struct AlertsResp: Decodable {
            struct Feature: Decodable { let properties: Props }
            struct Props: Decodable {
                let event: String?
                let headline: String?
                let severity: String?
                let ends: String?
                let expires: String?
            }
            let features: [Feature]
        }
        guard let url = URL(string: "https://api.weather.gov/alerts/active?point=\(lat),\(lon)") else {
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let payload = try? JSONDecoder().decode(AlertsResp.self, from: data)
        else { return [] }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        return payload.features.compactMap { f -> WeatherSnapshot.SevereAlert? in
            guard let event = f.properties.event, !event.isEmpty else { return nil }
            let ends = (f.properties.ends ?? f.properties.expires).flatMap { iso.date(from: $0) }
            return WeatherSnapshot.SevereAlert(
                event: event,
                severity: WeatherSnapshot.AlertSeverity(capString: f.properties.severity),
                headline: f.properties.headline,
                endsAt: ends
            )
        }
        .sorted { $0.severity.rank > $1.severity.rank }
    }

    /// Fold NWS's interleaved day/night period list into 6 daily
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
        return byDay.prefix(6).map { entry -> WeatherSnapshot.DailyForecast in
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
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_gusts_10m,weather_code"),
            URLQueryItem(name: "hourly", value: "visibility,temperature_2m,weather_code,precipitation_probability,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "forecast_days", value: "6"),
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

        // Pull the 6-day daily block into driver-facing entries. The
        // weekday label is localized against the IANA timezone Open-Meteo
        // resolves for the coordinate, so drivers crossing timezones
        // during a haul still see the right day chip on each card.
        let daily: [WeatherSnapshot.DailyForecast] = Self.composeOpenMeteoDaily(
            payload: payload
        )

        // Level-100 depth — feels-like / humidity / gust from the
        // `current` block; hourly band from the parallel hourly arrays
        // starting at the slot nearest now. Open-Meteo ships no CAP
        // bulletins, so `alerts` stays honestly empty on this path.
        let feelsLikeF: Int? = payload.current.apparent_temperature.map { Int($0.rounded()) }
        let humidityPct: Int? = payload.current.relative_humidity_2m.map { Int($0.rounded()) }
        let windGustMph: Int? = payload.current.wind_gusts_10m.map { Int($0.rounded()) }
        let hourly: [WeatherSnapshot.HourlyForecast] = Self.composeOpenMeteoHourly(payload: payload)
        let precipChancePct: Int? = hourly.first?.precipChancePct

        // 75th firing: `approximate` is always false now — the Dallas
        // fallback was removed, so we only reach this path for the
        // driver's real resolved coordinate.
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
            windGustMph: windGustMph,
            precipChancePct: precipChancePct,
            hourly: hourly
        )
        // v2: name the real provider (Open-Meteo) + infer the custom
        // glyph code from the symbol. Open-Meteo ships no CAP alerts, so
        // `alert` stays honestly nil on this path.
        snap.dataSource = .openMeteo
        snap.weatherCode = WeatherIcons.code(forSymbol: symbol)
        snap.observedAt = Date()
        return snap
    }

    /// Fold Open-Meteo's parallel hourly arrays into the next-12-hours
    /// band. Index alignment is by timestamp (the same scheme the
    /// visibility lookup above uses); short arrays just truncate the
    /// band — no synthesized hours.
    private static func composeOpenMeteoHourly(
        payload: OpenMeteoResponse
    ) -> [WeatherSnapshot.HourlyForecast] {
        guard
            let times = payload.hourly?.time,
            let temps = payload.hourly?.temperature_2m,
            !times.isEmpty
        else { return [] }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: payload.timezone ?? "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let cutoff = Date().addingTimeInterval(-1800)
        var out: [WeatherSnapshot.HourlyForecast] = []
        for i in times.indices {
            guard out.count < 12 else { break }
            guard
                let date = df.date(from: times[i]),
                date >= cutoff,
                temps.indices.contains(i)
            else { continue }
            let code = (payload.hourly?.weather_code?.indices.contains(i) == true)
                ? payload.hourly!.weather_code![i] : 0
            let (_, symbol) = openMeteoCondition(for: code)
            let precip: Int? = {
                guard let arr = payload.hourly?.precipitation_probability,
                      arr.indices.contains(i) else { return nil }
                return arr[i]
            }()
            let wind: Int? = {
                guard let arr = payload.hourly?.wind_speed_10m,
                      arr.indices.contains(i) else { return nil }
                return Int(arr[i].rounded())
            }()
            out.append(WeatherSnapshot.HourlyForecast(
                date: date,
                tempF: Int(temps[i].rounded()),
                symbol: symbol,
                precipChancePct: precip,
                windMph: wind
            ))
        }
        return out
    }

    /// Parse the Open-Meteo daily block into our 6-day forecast array.
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
            let apparent_temperature: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double
            let wind_gusts_10m: Double?
            let weather_code: Int
        }
        struct Hourly: Decodable {
            let time: [String]
            let visibility: [Double]
            let temperature_2m: [Double]?
            let weather_code: [Int]?
            let precipitation_probability: [Int?]?
            let wind_speed_10m: [Double]?
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

        // Pull the first 6 days of the WeatherKit daily forecast into
        // the flip-side chip row. WeatherCard lays these horizontally
        // with equal flexible widths so the row stays complete on a
        // 6.1" iPhone without fabricating a trailing day.
        let daily: [WeatherSnapshot.DailyForecast] = {
            let weekdayFmt = DateFormatter()
            weekdayFmt.locale = .current
            weekdayFmt.dateFormat = "EEE"
            let cal = Calendar.current

            return weather.dailyForecast.forecast.prefix(6).enumerated().map { (i, day) in
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

        // Level-100 depth — feels-like / humidity / gust straight off
        // the WeatherKit current observation; hourly band from the next
        // 12 hours; alerts mapped onto the NWS CAP severity ladder.
        let feelsLikeF = Int(current.apparentTemperature.converted(to: .fahrenheit).value.rounded())
        let humidityPct = Int((current.humidity * 100).rounded())
        let windGustMph: Int? = current.wind.gust.map {
            Int($0.converted(to: .milesPerHour).value.rounded())
        }
        let now = Date()
        let hourly: [WeatherSnapshot.HourlyForecast] = weather.hourlyForecast.forecast
            .filter { $0.date >= now.addingTimeInterval(-1800) }
            .prefix(12)
            .map { hour in
                WeatherSnapshot.HourlyForecast(
                    date: hour.date,
                    tempF: Int(hour.temperature.converted(to: .fahrenheit).value.rounded()),
                    symbol: hour.symbolName,
                    precipChancePct: Int((hour.precipitationChance * 100).rounded()),
                    windMph: Int(hour.wind.speed.converted(to: .milesPerHour).value.rounded()),
                    weatherCode: WeatherIcons.code(forSymbol: hour.symbolName)
                )
            }
        let precipChancePct: Int? = hourly.first?.precipChancePct
        let alerts: [WeatherSnapshot.SevereAlert] = (weather.weatherAlerts ?? []).map { alert in
            let sev: WeatherSnapshot.AlertSeverity = {
                switch alert.severity {
                case .minor:    return .minor
                case .moderate: return .moderate
                case .severe:   return .severe
                case .extreme:  return .extreme
                default:        return .unknown
                }
            }()
            return WeatherSnapshot.SevereAlert(
                event: alert.summary,
                severity: sev,
                headline: nil,
                endsAt: nil
            )
        }

        var snap = WeatherSnapshot(
            city: city,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visibilityMi,
            condition: condition,
            symbol: symbol,
            nextAlert: nextAlert.isEmpty ? nil : nextAlert,
            accent: accent,
            daily: daily,
            feelsLikeF: feelsLikeF,
            humidityPct: humidityPct,
            windGustMph: windGustMph,
            precipChancePct: precipChancePct,
            hourly: hourly,
            alerts: alerts
        )
        // v2: name the real provider (Apple Weather) + infer the custom
        // glyph code from the WeatherKit symbol.
        snap.dataSource = .weatherKit
        snap.weatherCode = WeatherIcons.code(forSymbol: symbol)
        snap.observedAt = Date()
        if let top = alerts.max(by: { $0.severity.rank < $1.severity.rank }) {
            snap.alert = .init(title: top.event, severity: top.severity, until: top.endsAt)
        }
        return snap
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
        await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            let requestID = UUID()
            pendingLocation?.resume(returning: nil)
            pendingLocation = cont
            pendingLocationID = requestID
            locationManager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard self.pendingLocationID == requestID else { return }
                self.pendingLocation?.resume(returning: nil)
                self.pendingLocation = nil
                self.pendingLocationID = nil
            }
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
            self.pendingLocationID = nil
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.pendingLocation?.resume(returning: nil)
            self.pendingLocation = nil
            self.pendingLocationID = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        // Broadcast the auth change so home views can re-run their
        // weather fetch after the user taps Allow on the prompt.
        // Without this, the dashboard rendered empty on first launch
        // because `fetchCurrent()` had already finished (returning
        // nil for `.notDetermined`) and no signal told the view to
        // try again once the user responded.
        NotificationCenter.default.post(
            name: .eusoWeatherAuthorizationChanged,
            object: nil
        )
    }
}
