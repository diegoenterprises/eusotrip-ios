//
//  WeatherForLoad.swift
//  EusoTrip — the client contract for `weather.forLoad` (the canonical
//  per-load weather card). Decodes the server shape 1:1 (frontend/server/
//  routers/weather.ts → forLoad). Every numeric field is optional and stays
//  nil when the server sent null → the v3 widget renders an honest "—",
//  never a fabricated value. Mirrors the WeatherSnapshot Level-100 doctrine.
//
//  TARGET: EusoTrip/Models/WeatherForLoad.swift
//
//  Server shape (forLoad):
//    { available, loadId, loadNumber, mode, status,
//      origin:      { name, lat, lon, realtime } | null,
//      destination: { name, lat, lon, realtime } | null,
//      laneImpact:  LaneImpact | null,          // §3 contract
//      source, computedAt }
//

import Foundation
import SwiftUI

// MARK: - Enums

enum WeatherMode: String, Decodable, Hashable {
    case truck, rail, vessel, unknown

    init(server raw: String?) {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = WeatherMode(rawValue: value) ?? .unknown
    }
}

/// §3 risk ladder. `none` renders no danger treatment; the widget tints
/// the alert/peak column from `watch`+.
enum LaneRiskTier: String, Decodable, Hashable {
    case none, watch, elevated, severe, unknown
    init(server raw: String?) {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = LaneRiskTier(rawValue: value) ?? .unknown
    }

    /// Brand color for the risk pill / peak column (DesignSystem tokens).
    var color: Color {
        switch self {
        case .severe, .elevated: return Brand.danger
        case .watch:             return Brand.warning
        case .none:              return Brand.info
        case .unknown:           return Brand.neutral
        }
    }
    var isActionable: Bool {
        self != .none && self != .unknown
    }
}

// MARK: - WeatherForLoad

struct WeatherForLoad: Decodable, Hashable {
    let available: Bool
    let loadId: String
    let loadNumber: String?
    let modeRaw: String?
    let status: String?
    let origin: Endpoint?
    let destination: Endpoint?
    let laneImpact: LaneImpact?
    let source: String?
    let computedAt: String?

    enum CodingKeys: String, CodingKey {
        case available, loadId, loadNumber, status, origin, destination, laneImpact, source, computedAt
        case modeRaw = "mode"
    }

    var mode: WeatherMode { WeatherMode(server: modeRaw) }

    // MARK: Endpoint (origin / destination)

    struct Endpoint: Decodable, Hashable {
        let name: String
        let lat: Double?
        let lon: Double?
        let realtime: Realtime?
    }

    struct Realtime: Decodable, Hashable {
        let observedAt: String?
        let weatherCode: Int?
        let condition: String?
        let temperature: Double?
        let temperatureApparent: Double?
        let windGustMph: Double?
        let windSpeedMph: Double?
        let visibilityMi: Double?
        let humidity: Double?
        let precipitationProbability: Double?
    }

    // MARK: LaneImpact (§3 contract — discriminated on `available`)

    struct LaneImpact: Decodable, Hashable {
        let available: Bool
        let modeRaw: String?
        let loadNumber: String?
        let riskTierRaw: String?
        let headline: String?
        let peakLeg: PeakLeg?
        let drivers: [Driver]?
        let recommendation: Recommendation?
        let reason: String?      // present when available == false
        let source: String?
        let computedAt: String?

        enum CodingKeys: String, CodingKey {
            case available, loadNumber, headline, peakLeg, drivers, recommendation, reason, source, computedAt
            case modeRaw = "mode"
            case riskTierRaw = "riskTier"
        }

        var mode: WeatherMode { WeatherMode(server: modeRaw) }
        var riskTier: LaneRiskTier { LaneRiskTier(server: riskTierRaw) }

        struct PeakLeg: Decodable, Hashable { let label: String; let time: String }
        struct Driver: Decodable, Hashable, Identifiable {
            let field: String   // "PRECIP" | "CROSSWIND" | "VISIBILITY" | "YARD VIS" | "STREAMFLOW" | "SIG WAVE" | "GUST @ BERTH"
            let value: String   // display-formatted only when `available` is true
            let available: Bool?
            let unavailableReason: String?
            var id: String { field }

            var isAvailable: Bool {
                if let available { return available }
                let legacy = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return legacy != "—" && legacy != "-"
            }
        }
        struct Recommendation: Decodable, Hashable { let text: String; let action: String; let protects: String }
    }
}

// MARK: - v3 widget display helpers
// These map the decoded contract → the strings/glyphs the v3 bespoke widget
// renders. All return honest "—"/nil when the field is absent.

extension WeatherForLoad {
    var routeWeatherAuthority: WeatherRouteDataPolicy.Authority {
        WeatherRouteDataPolicy.authority(for: source)
    }

    var routeWeatherComputedAt: Date? {
        WeatherRouteDataPolicy.parseProviderDate(computedAt)
    }

    var routeWeatherObservedAt: Date? {
        WeatherRouteDataPolicy.parseProviderDate(origin?.realtime?.observedAt)
    }

    var displayLoadIdentifier: String {
        let human = loadNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return human.isEmpty ? loadId : human
    }

    /// The per-load card is route intelligence. Only HERE may drive the route
    /// surface. WeatherKit and OpenWeather remain ambient-only providers and
    /// cannot be promoted into route conditions by presentation code.
    func canRenderLiveRouteWeather(at date: Date = Date()) -> Bool {
        guard LatLongParser.validatedCoordinate(
                  latitude: origin?.lat,
                  longitude: origin?.lon
              ) != nil,
              available,
              mode != .unknown,
              routeWeatherAuthority == .here,
              !WeatherRouteDataPolicy.isSyntheticLoadIdentifier(displayLoadIdentifier),
              WeatherRouteDataPolicy.isFresh(routeWeatherComputedAt, at: date),
              WeatherRouteDataPolicy.isFresh(routeWeatherObservedAt, at: date) else {
            return false
        }
        return true
    }

    var routeWeatherAttribution: String {
        routeWeatherAuthority.attribution
    }

    /// Whole-degree temp for the hero, e.g. "88°" (origin "now").
    var heroTempDisplay: String {
        guard let value = WeatherNumeric.roundedInt(
            origin?.realtime?.temperature,
            allowed: WeatherNumeric.temperatureF
        ) else { return "—" }
        return "\(value)°"
    }
    var feelsLikeDisplay: String? {
        guard let value = WeatherNumeric.roundedInt(
            origin?.realtime?.temperatureApparent,
            allowed: WeatherNumeric.temperatureF
        ) else { return nil }
        return "Feels like \(value)°"
    }
    var conditionLine: String? { origin?.realtime?.condition }
    var locationName: String? { origin?.name }
    /// Apple WeatherKit weatherCode for the hero glyph (WeatherIcons.swift).
    var heroWeatherCode: Int { origin?.realtime?.weatherCode ?? 0 }

    /// The 4 hero metric tiles (wind · visibility · humidity · precip).
    /// Each is (key, value) with an honest dash when absent.
    var metricTiles: [(key: String, value: String)] {
        let rt = origin?.realtime
        func mph(_ value: Double?) -> String {
            WeatherNumeric.roundedInt(value, allowed: WeatherNumeric.windMph)
                .map { "\($0) mph" } ?? "—"
        }
        func mi(_ value: Double?) -> String {
            WeatherNumeric.finite(value, allowed: 0...1_000)
                .map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) mi" } ?? "—"
        }
        func pct(_ value: Double?) -> String {
            WeatherNumeric.roundedInt(value, allowed: WeatherNumeric.percent)
                .map { "\($0)%" } ?? "—"
        }
        return [
            ("WIND", mph(rt?.windSpeedMph)),
            ("VISIBILITY", mi(rt?.visibilityMi)),
            ("HUMIDITY", pct(rt?.humidity)),
            ("PRECIP", pct(rt?.precipitationProbability)),
        ]
    }

    /// True when the lane is in a state worth surfacing the Lane Impact card.
    var hasLaneRisk: Bool {
        guard let li = laneImpact, li.available else { return false }
        return li.mode != .unknown
            && li.riskTier.isActionable
            && WeatherRouteDataPolicy.authority(for: li.source) == .here
            && WeatherRouteDataPolicy.isFresh(
                WeatherRouteDataPolicy.parseProviderDate(li.computedAt)
            )
            && !WeatherRouteDataPolicy.isSyntheticLoadIdentifier(displayLoadIdentifier)
    }

    /// "updated 2m ago" from computedAt, or nil.
    var freshnessDisplay: String? {
        guard let date = routeWeatherComputedAt,
              let secs = WeatherNumeric.elapsedWholeSeconds(from: date) else { return nil }
        if secs < 60 { return "updated just now" }
        if secs < 3600 { return "updated \(secs / 60)m ago" }
        return "updated \(secs / 3600)h ago"
    }
}
