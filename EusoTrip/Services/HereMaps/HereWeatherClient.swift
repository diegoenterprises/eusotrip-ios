//
//  HereWeatherClient.swift
//  EusoTrip — REST client for HERE Destination Weather v3.
//
//  Endpoint:
//      GET https://weather.hereapi.com/v3/report
//
//  Required params:
//      - location=<lat>,<lng>
//      - products=<comma-separated list>
//                 observation | forecastHourly | forecastDaily
//                 | forecast7days | nwsAlerts | radar
//
//  Auth: `Authorization: Bearer <token>` via HEREAuthService (same
//        bearer that all HERE REST clients in this codebase share).
//        HERE accepts either apiKey query or Bearer; we standardise
//        on Bearer across the fleet.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

// MARK: - Response wire types

/// Top-level shape of `GET /v3/report`. The server echoes back one
/// entry per place that matched the request; for a single-location
/// query we only expect `places[0]`.
struct HereWeatherReport: Decodable {
    let places: [HereWeatherPlace]
}

struct HereWeatherPlace: Decodable {
    let address: HereWeatherAddress?
    /// Single current-conditions observation — present when
    /// `products` contained `observation`.
    let observations: HereWeatherObservations?
    /// Hourly forecast block — present when `products` contained
    /// `forecastHourly`.
    let hourlyForecasts: HereHourlyForecastBlock?
    /// Daily forecast block — present when `products` contained
    /// `forecastDaily` (or `forecast7days`).
    let dailyForecasts: HereDailyForecastBlock?
    /// National Weather Service alerts for the U.S. only — present
    /// when `products` contained `nwsAlerts`.
    let nwsAlerts: HereNWSAlertBlock?
}

struct HereWeatherAddress: Decodable {
    let city: String?
    let state: String?
    let stateCode: String?
    let countryCode: String?
    let postalCode: String?
}

/// Current-conditions wrapper. HERE returns `observations[] = [ one ]`
/// for a single-location call; we flatten to the first element via
/// `current`.
struct HereWeatherObservations: Decodable {
    let observations: [HereWeatherObservation]
    var current: HereWeatherObservation? { observations.first }
}

/// One observation tick. HERE returns many numerics as `Double` and
/// descriptions as localized strings — we keep both so the UI can
/// either render the numeric value or the human description.
struct HereWeatherObservation: Decodable {
    /// Celsius.
    let temperature: Double?
    /// Fahrenheit — HERE ships both when `locale=en-US`.
    let temperatureFahrenheit: Double?
    /// "What it feels like" ambient — distinct from raw temperature
    /// when heat index / wind chill kicks in.
    let comfort: Double?
    let comfortFahrenheit: Double?
    /// Relative humidity percentage (0-100).
    let humidity: Double?
    /// Beaufort-scale or m/s depending on locale; HERE also ships
    /// `windSpeedMph` + `windSpeedKmh` for convenience.
    let windSpeed: Double?
    let windSpeedMph: Double?
    let windSpeedKmh: Double?
    /// Wind direction descriptive string (e.g. "NE").
    let windDesc: String?
    /// Localized description ("Partly cloudy", "Light rain", etc.).
    let description: String?
    /// HERE icon id — maps to brand weather glyphs.
    let iconName: String?
    let iconId: Int?
    /// Visibility in miles / km.
    let visibility: Double?
    /// ISO8601 timestamp.
    let daylight: String?
    let timeZoneOffset: String?
}

struct HereHourlyForecastBlock: Decodable {
    let forecasts: [HereHourlyForecast]
}

struct HereHourlyForecast: Decodable {
    let time: String?
    let description: String?
    let iconName: String?
    let iconId: Int?
    let temperature: Double?
    let temperatureFahrenheit: Double?
    let precipitationProbability: Double?
    let windSpeed: Double?
    let windSpeedMph: Double?
}

struct HereDailyForecastBlock: Decodable {
    let forecasts: [HereDailyForecast]
}

struct HereDailyForecast: Decodable {
    let date: String?
    let weekday: String?
    let description: String?
    let iconName: String?
    let highTemperature: Double?
    let highTemperatureFahrenheit: Double?
    let lowTemperature: Double?
    let lowTemperatureFahrenheit: Double?
    let precipitationProbability: Double?
    let windSpeedMph: Double?
}

struct HereNWSAlertBlock: Decodable {
    let alerts: [HereNWSAlert]?
}

/// One U.S. National Weather Service alert. HERE passes through the
/// NWS event type, severity, start/end, and a short description so
/// the UI can decide whether to surface it as a warning chip or hide
/// it (e.g. advisories vs. warnings).
struct HereNWSAlert: Decodable, Identifiable {
    var id: String { "\(type ?? "")-\(validFromTimeLocal ?? "")" }
    let type: String?
    let description: String?
    /// "Minor" | "Moderate" | "Severe" | "Extreme"
    let severity: String?
    let validFromTimeLocal: String?
    let validUntilTimeLocal: String?
}

// MARK: - Product set

enum HereWeatherProduct: String, CaseIterable {
    case observation
    case forecastHourly
    case forecastDaily
    case forecast7days
    case nwsAlerts
    case radar
}

// MARK: - Client

final class HereWeatherClient {
    static let shared = HereWeatherClient()

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches a weather report at `center`. Defaults to the four
    /// products a driver needs on Home: current conditions, hourly
    /// forecast, daily forecast, and U.S. NWS alerts. Pass
    /// `products: [.observation]` for the smallest payload when only
    /// the current chip is needed.
    func report(
        at center: CLLocationCoordinate2D,
        products: [HereWeatherProduct] = [.observation, .forecastHourly, .forecastDaily, .nwsAlerts]
    ) async throws -> HereWeatherPlace {
        var comps = URLComponents(string: "https://weather.hereapi.com/v3/report")!
        comps.queryItems = [
            URLQueryItem(name: "location", value: "\(center.latitude),\(center.longitude)"),
            URLQueryItem(name: "products", value: products.map(\.rawValue).joined(separator: ","))
        ]
        guard let url = comps.url else { throw HereMapsError.badURL }

        let data = try await HereBearerFetch.data(for: url, session: session)
        do {
            let report = try decoder.decode(HereWeatherReport.self, from: data)
            guard let place = report.places.first else {
                throw HereMapsError.emptyResponse
            }
            return place
        } catch let e as HereMapsError {
            throw e
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }
}
