//
//  HereGeocodingClient.swift
//  EusoTrip — REST client for HERE Geocoding & Search v7
//
//  Endpoints:
//    GET https://geocode.search.hereapi.com/v1/geocode?q=<address>
//    GET https://revgeocode.search.hereapi.com/v1/revgeocode?at=<lat,lng>
//    GET https://autosuggest.search.hereapi.com/v1/autosuggest?q=<partial>&at=<lat,lng>
//
//  Auth: `Authorization: Bearer <token>` (OAuth2 via HEREAuthService).
//  No apikey query string.
//
//  Docs: https://developer.here.com/documentation/geocoding-search-api/
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

actor HereGeocodingClient {

    static let shared = HereGeocodingClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Forward geocoding (address → lat/lng)

    /// Forward geocode an address string.
    /// - Parameter query: "1234 Main St, Dallas, TX"
    /// - Parameter near: Optional "prefer results near this lat/lng" hint.
    /// - Parameter limit: 1–20. HERE default is 20.
    func geocode(query: String,
                 near: CLLocationCoordinate2D? = nil,
                 limit: Int = 5) async throws -> [HereGeocodeItem] {
        var comps = URLComponents(url: HereMapsConfig.geocodeBaseURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q",      value: query),
            URLQueryItem(name: "limit",  value: String(limit)),
        ]
        if let near {
            items.append(URLQueryItem(name: "at", value: HereRoutingClient.fmt(near)))
        }
        comps.queryItems = items

        guard let url = comps.url else { throw HereMapsError.badURL }
        let data = try await authorizedData(for: url)
        do {
            return try decoder.decode(HereGeocodeResponse.self, from: data).items
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }

    // MARK: - Reverse geocoding (lat/lng → address)

    func reverseGeocode(at coordinate: CLLocationCoordinate2D,
                        limit: Int = 1) async throws -> [HereGeocodeItem] {
        var comps = URLComponents(url: HereMapsConfig.reverseGeocodeBaseURL,
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "at",     value: HereRoutingClient.fmt(coordinate)),
            URLQueryItem(name: "limit",  value: String(limit)),
        ]
        guard let url = comps.url else { throw HereMapsError.badURL }
        let data = try await authorizedData(for: url)
        do {
            return try decoder.decode(HereGeocodeResponse.self, from: data).items
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }

    // MARK: - Autosuggest (address picker)

    /// For address-picker UI. HERE requires the `at=` hint to rank locally.
    func autosuggest(query: String,
                     near: CLLocationCoordinate2D,
                     limit: Int = 8) async throws -> [HereGeocodeItem] {
        var comps = URLComponents(url: HereMapsConfig.autosuggestBaseURL,
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "q",      value: query),
            URLQueryItem(name: "at",     value: HereRoutingClient.fmt(near)),
            URLQueryItem(name: "limit",  value: String(limit)),
        ]
        guard let url = comps.url else { throw HereMapsError.badURL }
        let data = try await authorizedData(for: url)
        do {
            return try decoder.decode(HereGeocodeResponse.self, from: data).items
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }

    // MARK: - Helpers

    /// GET `url` with `Authorization: Bearer <token>`. On HTTP 401, invalidate
    /// the cached token and retry once before surfacing the error.
    private func authorizedData(for url: URL) async throws -> Data {
        func attempt() async throws -> (Data, HTTPURLResponse) {
            let token = try await HereMapsConfig.requireBearerToken()
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw HereMapsError.providerError("No HTTP response")
            }
            return (data, http)
        }

        var (data, http) = try await attempt()
        if http.statusCode == 401 {
            await HEREAuthService.shared.invalidate()
            (data, http) = try await attempt()
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HereMapsError.http(http.statusCode, body)
        }
        return data
    }
}

// MARK: - Bridge to LoadLocation

extension HereGeocodeItem {
    /// Converts a HERE geocode hit to EusoTrip's `LoadLocation`.
    func asLoadLocation() -> LoadLocation {
        LoadLocation(
            address:  [address.houseNumber, address.street].compactMap { $0 }.joined(separator: " "),
            city:     address.city ?? "",
            state:    address.stateCode ?? address.state ?? "",
            zipCode:  address.postalCode ?? "",
            lat:      position.lat,
            lng:      position.lng
        )
    }
}
