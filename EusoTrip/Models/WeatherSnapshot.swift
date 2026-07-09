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

// Level-100 / always-on doctrine (2026-06-19): the home weather widget
// must NEVER show "unavailable". The whole snapshot graph is `Codable`
// so the last-good REAL reading can be persisted to disk (UserDefaults
// JSON) and survive a cold relaunch — see `WeatherService.cachedSnapshot`.
// Codability is render-fidelity-preserving (hourly + daily + alerts +
// lane impact all round-trip); the computed `Color` helpers on the enums
// are unaffected (computed props aren't encoded). Nothing fabricated:
// only a genuinely fetched snapshot is ever written.
struct WeatherSnapshot: Hashable, Codable {
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
    /// Retained for the legacy compact paths + accessibility text; the v2
    /// expanded surface draws the custom `WeatherIcons` glyph keyed off
    /// `weatherCode` instead.
    let symbol: String

    // ── Apple WeatherKit v2 backbone ─────────────────────────────────────
    //
    // The Apple WeatherKit `weatherCode` (the exact field — NOT the
    // Day/Night/FullDay variants) is the single source of truth for the
    // custom glyph set in `WeatherIcons.swift`. Defaults to 0 ("Unknown")
    // so the legacy WeatherKit / NWS / Open-Meteo compose paths — which
    // pre-date the Apple WeatherKit wiring and only know SF Symbols — still
    // build and render their `#i-cloud` fallback honestly. The mapper
    // also infers a best-effort code from the SF symbol so those paths
    // light a real glyph rather than the unknown cloud.
    var weatherCode: Int = 0

    /// Where this snapshot came from — drives the attribution line
    /// ("Conditions · Apple WeatherKit" only when Apple WeatherKit actually
    /// produced the data; never fabricated onto a fallback).
    var dataSource: DataSource = .unknown

    /// UV index 0–11+. Nil when the source omits it.
    var uvIndex: Int? = nil

    /// Highest-priority active government bulletin in the v2 single-alert
    /// shape (title/severity/until). Distinct from `alerts[]` (the full
    /// CAP list the flip side renders); this is the one the hero alert
    /// bar + collapsed pill show. Nil → no bar/pill rendered (honest:
    /// "no alert" is live information, never a fabricated "all clear").
    var alert: ActiveAlert? = nil

    /// Per-load ETA-risk segments for the LANE IMPACT panel — populated
    /// by `weather.laneImpact` (Apple WeatherKit `/v4/route`, time-aware).
    /// Nil/empty → the panel collapses (between loads, Enterprise route
    /// tier absent, or the call returned no data). Never seeded.
    var laneImpact: [LaneImpactSegment]? = nil

    /// When this snapshot was produced (server `updatedAt` or fetch
    /// time). Drives "updated Nm ago". Nil → that clause is omitted.
    var observedAt: Date? = nil

    // ── Sky-engine fields (time-of-day · season · moon) ─────────────
    //
    // build-751 weather overhaul: the continuous animated sky needs the
    // REAL observation geometry to choose the right scene — sun-arc angle,
    // season palette, day/night split, moon phase. Every field is optional
    // + Codable + persisted with the rest of the snapshot, so a cold
    // relaunch repaints the correct scene instantly. Honest: each value is
    // derived from a real upstream field (CLLocation, server daily, the
    // observation clock) — never fabricated. When a field is absent the
    // computed helpers fall back to a safe, nil-safe default (northern
    // hemisphere, hour-gated day/night) rather than inventing data.

    /// Latitude of the observation point (-90…+90 deg). From the resolved
    /// CLLocation. Drives the sun/moon arc angle, season, and hemisphere.
    var latitude: Double? = nil

    /// IANA timezone identifier ("America/Chicago", "Europe/London") for
    /// the observation point. From the CLPlacemark's timeZone (or server).
    /// Drives local-time computation for the day-part split.
    var timezoneId: String? = nil

    /// Sunrise at this location/day. Extracted from the server daily strip
    /// (or NWS period boundaries). Drives the honest day/night + dawn/dusk
    /// transitions. Nil → the helpers fall back to an hour gate.
    var sunriseAt: Date? = nil

    /// Sunset at this location/day. Pairs with `sunriseAt`.
    var sunsetAt: Date? = nil

    /// Explicit night flag when an upstream source states it (e.g. a
    /// WeatherKit symbol that carries `.fill` night variants, or a server
    /// `isDaytime: false`). Honest override; when nil, `isNight` derives
    /// from sunrise/sunset → hour gate.
    var isNightHint: Bool? = nil
    /// "5h · light rain · pickup window" — the driver-actionable forecast line.
    let nextAlert: String?
    /// Accent color choice — blue for clear/dry, warning for hazard watch.
    let accent: Accent
    /// 6-day look-ahead rendered on the flip side of the card. First
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
    /// Apple WeatherKit minute-by-minute precipitation for the next
    /// hour. Nil when the source/region does not supply minute data.
    var nextHourPrecip: NextHourPrecip? = nil
    /// Next ~12 hours, hourly. Empty when the source had no hourly block.
    var hourly: [HourlyForecast] = []
    /// Active severe-weather bulletins (NWS-style severity). Empty =
    /// no active alerts — which is itself live information.
    var alerts: [SevereAlert] = []

    /// One hour in the hourly band.
    struct HourlyForecast: Hashable, Codable, Identifiable {
        let date: Date
        let tempF: Int
        /// SF Symbol for the hour's condition (legacy paths + a11y).
        let symbol: String
        /// 0–100, nil when not supplied.
        let precipChancePct: Int?
        /// mph, nil when not supplied.
        let windMph: Int?
        /// Apple WeatherKit weatherCode for the hour — drives the v2 custom
        /// glyph in the 8-hour strip. Defaults to 0; the WeatherIcons
        /// mapper infers from `symbol` when this is unset so the legacy
        /// paths still render a real glyph.
        var weatherCode: Int = 0

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

    /// WeatherKit's next-hour minute precipitation data. The app uses
    /// this for Apple Weather-style "rain starting soon" copy, but only
    /// when a real minute forecast exists for the coordinate.
    struct NextHourPrecip: Hashable, Codable {
        let forecastStart: Date?
        let forecastEnd: Date?
        let minutes: [Minute]
        let summaries: [Summary]

        struct Minute: Hashable, Codable, Identifiable {
            let date: Date
            let precipChancePct: Int?
            let intensityMmPerHour: Double?

            var id: Date { date }
        }

        struct Summary: Hashable, Codable, Identifiable {
            let start: Date
            let end: Date?
            let precipChancePct: Int?
            let intensityMmPerHour: Double?
            let precipitationType: String?

            var id: Date { start }
        }

        var peakMinute: Minute? {
            minutes.max { lhs, rhs in
                let lChance = lhs.precipChancePct ?? 0
                let rChance = rhs.precipChancePct ?? 0
                if lChance != rChance { return lChance < rChance }
                return (lhs.intensityMmPerHour ?? 0) < (rhs.intensityMmPerHour ?? 0)
            }
        }

        var nextMeaningfulMinute: Minute? {
            let cutoff = Date().addingTimeInterval(-60)
            return minutes.first { minute in
                minute.date >= cutoff &&
                ((minute.precipChancePct ?? 0) >= 35 || (minute.intensityMmPerHour ?? 0) > 0)
            }
        }

        var dominantPrecipitationType: String? {
            summaries.first(where: { ($0.precipChancePct ?? 0) >= 35 || ($0.intensityMmPerHour ?? 0) > 0 })?
                .precipitationType
        }

        var displayLine: String? {
            guard let minute = nextMeaningfulMinute ?? peakMinute,
                  let chance = minute.precipChancePct,
                  chance >= 25 || (minute.intensityMmPerHour ?? 0) > 0 else { return nil }
            let now = Date()
            let delta = Int(minute.date.timeIntervalSince(now) / 60.0)
            let label = Self.precipitationLabel(for: dominantPrecipitationType)
            if delta <= 1 {
                return "\(label) now · \(chance)%"
            }
            if delta < 60 {
                return "\(label) starts in \(delta) min · \(chance)%"
            }
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("h:mm a")
            return "\(label) near \(f.string(from: minute.date)) · \(chance)%"
        }

        private static func precipitationLabel(for raw: String?) -> String {
            switch (raw ?? "").lowercased() {
            case "snow": return "Snow"
            case "sleet", "hail", "mixed": return "Ice"
            case "rain": return "Rain"
            default: return "Precip"
            }
        }
    }

    /// One active severe-weather bulletin. Severity vocabulary follows
    /// NWS CAP ("Minor" | "Moderate" | "Severe" | "Extreme") — the same
    /// strings HERE Destination Weather passes through on `nwsAlerts`
    /// and api.weather.gov returns on /alerts/active.
    struct SevereAlert: Hashable, Codable, Identifiable {
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
    enum AlertSeverity: String, Hashable, Codable, Comparable {
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

    /// A single day in the 6-day look-ahead.
    struct DailyForecast: Hashable, Codable, Identifiable {
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

    enum Accent: String, Hashable, Codable {
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

    // MARK: - Apple WeatherKit v2 supporting types

    /// Which upstream produced this snapshot. Only `.appleWeather` earns
    /// the "Conditions · Apple WeatherKit" attribution; the rest keep their
    /// own honest provenance so the source line never lies about where
    /// a number came from.
    enum DataSource: String, Hashable, Codable {
        case appleWeather   // server weather.byLatLon (Apple WeatherKit-backed)
        case weatherKit   // Apple WeatherKit
        case nws          // api.weather.gov
        case openMeteo    // open-meteo.com
        case here         // HERE Destination Weather (lane points)
        case unknown

        /// The attribution string shown on the expanded card's source
        /// line. Apple WeatherKit is the v2 backbone; every other provider
        /// is named truthfully rather than mislabeled as Apple WeatherKit.
        var attribution: String {
            switch self {
            case .appleWeather: return "Apple Weather"
            case .weatherKit: return "Apple Weather"
            case .nws:        return "NWS"
            case .openMeteo:  return "Open-Meteo"
            case .here:       return "HERE"
            case .unknown:    return "live source"
            }
        }
    }

    /// The single hero/collapsed government alert in the v2 shape. The
    /// CAP `alerts[]` array (used by the flip side) is the full list;
    /// this is the one promoted to the bar + pill.
    struct ActiveAlert: Hashable, Codable {
        /// "Flood watch"
        let title: String
        let severity: AlertSeverity
        /// When the bulletin expires — nil → open-ended/unknown.
        let until: Date?

        /// "until 7 PM" or nil.
        var untilDisplay: String? {
            guard let until else { return nil }
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("ha")
            return "until \(f.string(from: until))"
        }
    }

    /// Transport mode of a lane-impact segment — picks the mode chip
    /// glyph + tint in the LANE IMPACT panel.
    enum LaneMode: String, Hashable, Codable {
        case truck, rail, vessel

        var color: Color {
            switch self {
            case .truck:  return Brand.blue
            case .rail:   return Brand.rail
            case .vessel: return Brand.vessel
            }
        }
    }

    /// Coarse ETA-risk tier for a lane segment. Apple WeatherKit `/v4/route`
    /// worst-case → tier server-side; the client only renders it.
    ///
    /// §3 contract vocabulary is `none|watch|elevated|severe`. The legacy
    /// case was `.clear`; the server emits `"none"` (and "clear" for the
    /// older payloads), so the decoder maps both onto `.none`.
    enum RiskTier: String, Hashable, Codable, Comparable {
        case none, watch, elevated, severe

        var rank: Int {
            switch self {
            case .none:     return 0
            case .watch:    return 1
            case .elevated: return 2
            case .severe:   return 3
            }
        }

        var color: Color {
            switch self {
            case .none:     return Brand.success
            case .watch:    return Brand.warning
            case .elevated: return Brand.warning
            case .severe:   return Brand.danger
            }
        }

        static func < (lhs: RiskTier, rhs: RiskTier) -> Bool { lhs.rank < rhs.rank }
    }

    /// §3 `peakLeg: { label, time } | null` — the worst leg the route
    /// reduction surfaced ("I-35", "4 PM"). Drawn as the danger band's
    /// position + label on the route-cell diagram.
    struct PeakLeg: Hashable, Codable {
        /// "I-35" / "Lenexa–Shawnee segment" / "Port of Houston berth".
        let label: String
        /// "4 PM" / "14:00–18:00".
        let time: String

        /// "I-35 · 4 PM" — the combined chip text.
        var display: String {
            let l = label.trimmingCharacters(in: .whitespaces)
            let t = time.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { return t }
            if t.isEmpty { return l }
            return "\(l) · \(t)"
        }
    }

    /// §3 `drivers: { field, value }[]` — one mode-specific metric tile.
    /// Tri-modal worst-case fields (truck PRECIP/CROSSWIND/VISIBILITY ·
    /// rail YARD VIS/CROSSWIND/STREAMFLOW · vessel SIG WAVE/GUST @ BERTH/
    /// VISIBILITY). `value` is the formatted live reading or "—" when the
    /// Apple WeatherKit field was absent — never fabricated.
    struct Driver: Hashable, Codable, Identifiable {
        /// "CROSSWIND" / "SIG WAVE" / "STREAMFLOW".
        let field: String
        /// "31 mph" / "2.4 m" / "Rising" / "—".
        let value: String

        var id: String { field }
    }

    /// §3 `recommendation: { text, action, protects }` — ESang's one
    /// actionable suggestion, server-authored from the route reduction.
    /// `action` is the highlighted verb-phrase ("Move pickup to 1:30 PM"),
    /// `protects` the outcome it preserves ("the Dallas appointment").
    struct Recommendation: Hashable, Codable {
        /// The framing clause — "the cell crosses the I-35 leg at 4 PM".
        let text: String
        /// The highlighted action — "Move pickup to 1:30 PM".
        let action: String
        /// What it protects — "the Dallas appointment".
        let protects: String
    }

    /// One load's weather-driven ETA risk on its lane — the LANE IMPACT
    /// differentiator. Conforms verbatim to the §3 `LaneImpact` contract
    /// (`loadId · mode · riskTier · headline · peakLeg{label,time} ·
    /// drivers[]{field,value} · recommendation{text,action,protects} ·
    /// source · computedAt`). Every field is server-derived from the live
    /// `/v4/route` reduction (worst-case precip / gust / visibility per
    /// leg) → never invented client-side.
    ///
    /// The `route` / `pickupTime` / `etaDelayMin` / `esangSuggestion`
    /// fields are EusoTrip render helpers retained alongside the contract
    /// (the route-cell diagram needs the lane string + pickup; the
    /// collapsed strip needs the compact delay). When the server supplies
    /// the structured §3 form the diagram + ESang panel read from it;
    /// when only the legacy flat form arrives they degrade through these.
    struct LaneImpactSegment: Hashable, Codable, Identifiable {
        // ── §3 contract fields ──────────────────────────────────────
        /// "LD-260615"
        let loadId: String
        let mode: LaneMode
        let riskTier: RiskTier
        /// §3 `headline` — "+40 min ETA risk" | "~6h dwell" |
        /// "Crane hold 14:00–18:00". The big risk readout in the route
        /// footer. Empty → derived from `etaDelayMin`.
        let headline: String
        /// §3 `peakLeg: { label, time } | null` — the worst leg + its
        /// time. Drives the danger-band position + "4 PM CELL" label.
        let peakLeg: PeakLeg?
        /// §3 `drivers` — the 3 mode-specific metric tiles. Each value is
        /// a live worst-case reading or "—". Empty → tiles collapse.
        let drivers: [Driver]
        /// §3 `recommendation: { text, action, protects }`. Nil → the
        /// ESang orb line collapses.
        let recommendation: Recommendation?
        /// §3 `computedAt` — when the route reduction ran. Nil → omitted.
        let computedAt: Date?

        // ── EusoTrip render helpers (alongside the contract) ─────────
        /// "Austin → Dallas · I-35" — the lane string the route-cell
        /// diagram labels its origin/destination nodes from.
        let route: String
        /// Scheduled pickup time the route call was anchored to.
        let pickupTime: Date?
        /// Estimated ETA delay in minutes from the weather on the lane.
        /// Nil → no measurable delay (the footer shows "on time").
        let etaDelayMin: Int?
        /// Legacy flat ESang line — server-authored. Used only when the
        /// structured `recommendation` is absent (older payloads).
        let esangSuggestion: String?

        var id: String { loadId }

        /// The risk readout shown in the route footer — the §3 `headline`
        /// when present, else the derived ETA-delay form.
        var headlineDisplay: String {
            let h = headline.trimmingCharacters(in: .whitespaces)
            return h.isEmpty ? etaDelayDisplay : h
        }

        /// "+40 min" / "+1 min" / "on time".
        var etaDelayDisplay: String {
            guard let m = etaDelayMin, m > 0 else { return "on time" }
            return "+\(m) min"
        }

        /// "+40m" — compact form for the collapsed lane strip.
        var etaDelayCompact: String {
            guard let m = etaDelayMin, m > 0 else { return "on time" }
            return "+\(m)m"
        }

        /// "pickup 3:30 PM" or nil.
        var pickupDisplay: String? {
            guard let pickupTime else { return nil }
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("h:mm a")
            return "pickup \(f.string(from: pickupTime))"
        }

        /// The label drawn under the route's origin node — the first
        /// segment of `route` (before "→"), uppercased. "" when absent.
        var originLabel: String {
            routeEndpoints.origin
        }

        /// The label drawn under the route's destination node — the
        /// second segment of `route` (after "→"), uppercased.
        var destinationLabel: String {
            routeEndpoints.destination
        }

        /// Split "Austin → Dallas · I-35" into ("AUSTIN", "DALLAS · I-35").
        private var routeEndpoints: (origin: String, destination: String) {
            let parts = route.components(separatedBy: "→")
            guard parts.count >= 2 else {
                return (route.uppercased(), "")
            }
            let o = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let d = parts[1].trimmingCharacters(in: .whitespaces).uppercased()
            return (o, d)
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

    // ── Apple WeatherKit v2 display helpers ──────────────────────────────

    /// "UV 7" or "—".
    var uvDisplay: String {
        guard let uv = uvIndex else { return "—" }
        return "UV \(uv)"
    }

    /// "18%" precip chance or "—".
    var precipChanceDisplay: String {
        guard let p = precipChancePct else { return "—" }
        return "\(p)%"
    }

    /// Visibility "10 mi".
    var visibilityDisplay: String { "\(visibilityMi) mi" }

    /// "Rain chance 60% near 5 PM" / "Precip likely this hour · 70%" /
    /// alert title. Derived only from live current/hourly/alert fields.
    var nextWeatherDisplay: String? {
        if let alert = heroAlert {
            return [alert.title, alert.untilDisplay].compactMap { $0 }.joined(separator: " · ")
        }
        if let display = nextHourPrecip?.displayLine {
            return display
        }
        if let p = precipChancePct, p >= 50 {
            return "Precip likely this hour · \(p)%"
        }
        let now = Date()
        if let hour = hourly.first(where: { hour in
            hour.date >= now && (hour.precipChancePct ?? 0) >= 40
        }) {
            let event = precipitationLabel(for: hour.weatherCode)
            return "\(event) chance \(hour.precipChancePct ?? 0)% near \(hour.hourLabel)"
        }
        if let peak = peakHourIndex, hourly.indices.contains(peak) {
            let hour = hourly[peak]
            let event = precipitationLabel(for: hour.weatherCode)
            return "\(event) watch near \(hour.hourLabel)"
        }
        if let uvIndex, uvIndex >= 8 {
            return "High UV now · UV \(uvIndex)"
        }
        return nextAlert
    }

    private func precipitationLabel(for code: Int) -> String {
        switch code {
        case 8000: return "Storm"
        case 5000, 5001, 5100, 5101: return "Snow"
        case 6000, 6001, 6200, 6201, 7000, 7101, 7102: return "Ice"
        default: return "Rain"
        }
    }

    /// The hero/collapsed alert, preferring the explicit v2 `alert` and
    /// falling back to the top CAP bulletin so legacy paths that only
    /// populate `alerts[]` still light the bar.
    var heroAlert: ActiveAlert? {
        if let alert { return alert }
        guard let top = topAlert else { return nil }
        return ActiveAlert(title: top.event, severity: top.severity, until: top.endsAt)
    }

    /// The v2 attribution line:
    /// "Conditions · Apple Weather · Mostly cloudy · updated 2m ago".
    /// Each clause is omitted honestly when its data is absent. The
    /// internal `weatherCode` remains available for glyph logic, but it
    /// is not user-facing copy.
    var attributionLine: String {
        var parts: [String] = ["Conditions", dataSource.attribution]
        let cleanedCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedCondition.isEmpty,
           cleanedCondition != "—",
           cleanedCondition.lowercased() != "unknown" {
            parts.append(cleanedCondition)
        }
        if let updated = updatedAgoDisplay {
            parts.append("updated \(updated)")
        }
        return parts.joined(separator: " · ")
    }

    /// "2m ago" / "just now" / "1h ago" — nil when `observedAt` unknown.
    var updatedAgoDisplay: String? {
        guard let observedAt else { return nil }
        let secs = max(0, Int(Date().timeIntervalSince(observedAt)))
        if secs < 60 { return "just now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m ago" }
        let hours = mins / 60
        return "\(hours)h ago"
    }

    /// Index of the "peak" hour in `hourly` to highlight in the v2 strip
    /// — the hour with the most hazardous condition (worst weatherCode
    /// severity, breaking ties by highest precip chance). Nil when the
    /// band is empty or nothing rises above benign. Derived strictly
    /// from live hourly readings — never a fabricated spike.
    var peakHourIndex: Int? {
        guard !hourly.isEmpty else { return nil }
        func hazard(_ h: HourlyForecast) -> Int {
            // Severity bucket from the Apple WeatherKit code family (or 0).
            let code = h.weatherCode
            let bucket: Int
            switch code {
            case 8000:                          bucket = 5   // thunderstorm
            case 4201, 6201, 7101:              bucket = 4   // heavy rain / freezing / ice
            case 4001, 5101, 6001, 6200, 7000:  bucket = 3   // rain / heavy snow / freezing
            case 4000, 4200, 5000, 5001, 5100, 6000, 7102: bucket = 2 // drizzle / snow / sleet
            case 2000, 2100:                    bucket = 1   // fog
            default:                            bucket = 0
            }
            return bucket * 1000 + (h.precipChancePct ?? 0)
        }
        let scored = hourly.enumerated().max { hazard($0.element) < hazard($1.element) }
        guard let best = scored, hazard(best.element) > 0 else { return nil }
        return best.offset
    }

    /// The collapsed dashboard "lane strip" line: "2 active loads in
    /// this cell · LD-260615". Nil when there's no lane impact. Honest:
    /// the count is the real segment count, the id is the worst-risk
    /// load's id.
    var collapsedLaneStrip: (text: String, loadId: String, delay: String)? {
        guard let segs = laneImpact, !segs.isEmpty else { return nil }
        let worst = segs.max { $0.riskTier < $1.riskTier } ?? segs[0]
        let noun = segs.count == 1 ? "load" : "loads"
        return (
            text: "\(segs.count) active \(noun) in this cell",
            loadId: worst.loadId,
            delay: worst.etaDelayCompact
        )
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

    // ── Sky-engine geometry (time-of-day · season · moon) ───────────
    //
    // build-751: the animated sky reads these to pick the scene. All are
    // derived from the REAL fields above (latitude, sunriseAt/sunsetAt,
    // observedAt) via the pure helpers at file scope so the engine, a unit
    // test, and a SwiftUI preview all compute identically. Nothing is
    // fabricated: when an input is nil the helper falls back honestly
    // (hour gate for day/night, northern hemisphere for season).

    /// The clock instant the scene is anchored to — the real observation
    /// time when known, else now. Centralised so every helper agrees.
    var clockReference: Date { observedAt ?? Date() }

    /// True when the location is currently in night. Honest priority:
    ///   1. an explicit upstream night hint (`isNightHint`),
    ///   2. the real sunrise/sunset window,
    ///   3. an hour gate (≥ 20:00 or < 06:00 local) as last resort.
    /// Never fabricates daylight — a missing sun pair degrades to the gate.
    var isNight: Bool {
        if let hint = isNightHint { return hint }
        let now = clockReference
        if let rise = sunriseAt, let set = sunsetAt {
            return !(now >= rise && now < set)
        }
        var cal = Calendar.current
        if let tz = timezoneId, let zone = TimeZone(identifier: tz) {
            cal.timeZone = zone
        }
        let h = cal.component(.hour, from: now)
        return h >= 20 || h < 6
    }

    /// Convenience inverse used by the palette selector.
    var isDaytime: Bool { !isNight }

    /// Hemisphere from latitude. Defaults to northern when latitude is
    /// absent (the safe majority assumption — never blocks the scene).
    var hemisphere: Hemisphere {
        guard let lat = latitude else { return .northern }
        return lat >= 0 ? .northern : .southern
    }

    /// Meteorological season for the observation, hemisphere-aware.
    var season: Season {
        WeatherSnapshot.seasonFor(date: clockReference, latitude: latitude)
    }

    /// Fine-grained part of the local day the scene should render
    /// (dawn / morning / noon / afternoon / dusk / night). Honest: built
    /// from the real sun pair when present, else the hour gate.
    var dayPart: DayPart {
        WeatherSnapshot.dayPartFor(
            date: clockReference,
            sunrise: sunriseAt,
            sunset: sunsetAt,
            timezoneId: timezoneId
        )
    }

    /// Moon illumination + phase name (0…1). Derived purely from the
    /// observation date against the astronomical new-moon epoch.
    var moonPhase: MoonPhase {
        WeatherSnapshot.computeMoonPhase(date: clockReference)
    }

    // MARK: - Sky-engine value types

    enum Hemisphere: String, Hashable, Codable { case northern, southern }

    enum Season: String, Hashable, Codable {
        case spring, summer, fall, winter
    }

    /// Six day-parts the sky palette keys off. `night` covers everything
    /// after dusk and before dawn.
    enum DayPart: String, Hashable, Codable {
        case dawn, morning, noon, afternoon, dusk, night

        /// True for the two twilight bands (the golden/blue-hour scenes).
        var isTwilight: Bool { self == .dawn || self == .dusk }
    }

    /// Moon illumination fraction (0…1) + the eight canonical phase names.
    /// `illumination` is the lit fraction of the disc (0 = new, 1 = full);
    /// `fraction` is the 0…1 position through the synodic month (drives
    /// waxing vs waning so the renderer shadows the correct limb).
    struct MoonPhase: Hashable, Codable {
        /// 0…1 lit fraction of the disc — peaks at full.
        let illumination: Double
        /// 0…1 position through the lunation (0/1 = new, 0.5 = full).
        let fraction: Double
        /// "new" / "waxing crescent" / … / "waning crescent".
        let name: String

        /// True for the first half of the cycle (new → full): the disc
        /// lights from the right limb. False = waning (lights from left).
        var isWaxing: Bool { fraction < 0.5 }
    }

    // MARK: - Pure helpers (engine · tests · previews share one path)

    /// Moon illumination + phase from a date. Lunation = 29.53059 days
    /// measured from the 2000-01-06 18:14 UTC astronomical new moon.
    /// Pure + deterministic — no `Date()`, no allocations beyond the
    /// returned value.
    static func computeMoonPhase(date: Date) -> MoonPhase {
        let synodicMonth = 29.530588853
        // 2000-01-06 18:14 UTC reference new moon.
        let newMoonRef = Date(timeIntervalSince1970: 947_182_440)
        let days = date.timeIntervalSince(newMoonRef) / 86_400.0
        var fraction = (days / synodicMonth).truncatingRemainder(dividingBy: 1.0)
        if fraction < 0 { fraction += 1.0 }           // pre-epoch dates
        // Lit fraction: 0 at new, 1 at full, symmetric across the month.
        let illumination = (1 - cos(2 * Double.pi * fraction)) / 2
        let name: String
        switch fraction {
        case 0..<0.0625, 0.9375...1.0: name = "new"
        case 0.0625..<0.1875:          name = "waxing crescent"
        case 0.1875..<0.3125:          name = "first quarter"
        case 0.3125..<0.4375:          name = "waxing gibbous"
        case 0.4375..<0.5625:          name = "full"
        case 0.5625..<0.6875:          name = "waning gibbous"
        case 0.6875..<0.8125:          name = "last quarter"
        default:                       name = "waning crescent"
        }
        return MoonPhase(illumination: illumination, fraction: fraction, name: name)
    }

    /// Meteorological season for a date, hemisphere-aware. A nil latitude
    /// assumes the northern hemisphere (safe default — never blocks).
    static func seasonFor(date: Date, latitude: Double?) -> Season {
        let month = Calendar.current.component(.month, from: date)
        let northern = (latitude ?? 0) >= 0
        // Northern meteorological seasons; flip 6 months for the south.
        let northernSeason: Season
        switch month {
        case 3...5:   northernSeason = .spring
        case 6...8:   northernSeason = .summer
        case 9...11:  northernSeason = .fall
        default:      northernSeason = .winter   // 12, 1, 2
        }
        if northern { return northernSeason }
        switch northernSeason {
        case .spring: return .fall
        case .summer: return .winter
        case .fall:   return .spring
        case .winter: return .summer
        }
    }

    /// Fine-grained day-part from the local clock + the real sun pair.
    /// When sunrise/sunset are present the bands are anchored to them
    /// (dawn = 1h before sunrise → sunrise · dusk = sunset → 1h after);
    /// otherwise an hour gate in the location's timezone is used. Pure.
    static func dayPartFor(
        date: Date,
        sunrise: Date?,
        sunset: Date?,
        timezoneId: String?
    ) -> DayPart {
        if let rise = sunrise, let set = sunset, set > rise {
            let dawnStart = rise.addingTimeInterval(-3600)
            let duskEnd   = set.addingTimeInterval(3600)
            // Quarter-day midpoints between sunrise and sunset.
            let daySpan   = set.timeIntervalSince(rise)
            let morningEnd   = rise.addingTimeInterval(daySpan * 0.30)
            let afternoonStart = set.addingTimeInterval(-daySpan * 0.30)
            if date < dawnStart        { return .night }
            if date < rise             { return .dawn }
            if date < morningEnd       { return .morning }
            if date < afternoonStart   { return .noon }
            if date < set              { return .afternoon }
            if date < duskEnd          { return .dusk }
            return .night
        }
        // Hour-gate fallback in the location's timezone (or device local).
        var cal = Calendar.current
        if let tz = timezoneId, let zone = TimeZone(identifier: tz) {
            cal.timeZone = zone
        }
        let h = cal.component(.hour, from: date)
        switch h {
        case 5..<7:   return .dawn
        case 7..<11:  return .morning
        case 11..<15: return .noon
        case 15..<18: return .afternoon
        case 18..<20: return .dusk
        default:      return .night
        }
    }
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
