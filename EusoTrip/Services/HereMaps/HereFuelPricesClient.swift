//
//  HereFuelPricesClient.swift
//  EusoTrip — REST client for HERE Fuel Prices API v3.
//
//  Endpoint:
//      GET https://fuel.hereapi.com/v3/stations
//
//  Required params:
//      - prox=<lat>,<lng>,<radius-meters>
//      - apiKey=<KEY>    OR    Authorization: Bearer <token>
//
//  Optional params used here:
//      - fuelType=1,11,55  — diesel-family codes (truck driver app).
//                            Omit to return every fuel type at each
//                            station.
//
//  Auth: we reuse the same OAuth Bearer token minted by
//  `HEREAuthService` that the Routing / Matrix / Geocoding / Tile
//  clients use. HERE accepts the Bearer across every REST product in
//  their Platform Portal, so no new credential is required beyond
//  what's already in `EusoTrip.xcconfig`. If the bearer is
//  unavailable, `HereMapsConfig.requireBearerToken()` throws and the
//  caller surfaces a neutral empty state — the existing doctrine on
//  "no fake data" applies here too: when HERE can't answer, the
//  fuel strip hides itself.
//
//  Docs: https://docs.here.com/fuel-prices/docs/
//        Fuel type codes: https://docs.here.com/fuel-prices/docs/fuel-types-mapping
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

// MARK: - Response wire types

/// Raw decoded shape of `GET /v3/stations`. The server returns a
/// top-level `fuelStations` array; each element is a `HereFuelStation`.
/// We keep the wire names verbatim so the decoder doesn't need a
/// `CodingKeys` override — HERE uses camelCase which matches Swift.
struct HereFuelStationsResponse: Decodable {
    let fuelStations: [HereFuelStation]
}

/// One station + its current per-fuel-type prices.
struct HereFuelStation: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let brand: String?
    let brandIcon: String?
    let position: HerePosition
    let address: HereFuelAddress?
    let distance: Int?
    let open24x7: Bool?
    let fuelPrice: [HereFuelPrice]?
    let lastUpdateTimestamp: String?

    /// Convenience — the cheapest diesel-family price at this station,
    /// or nil when HERE returned no diesel entries. Filters by the
    /// canonical diesel + truck-diesel + premium-diesel codes from
    /// HERE's fuel-types mapping.
    var cheapestDieselPrice: HereFuelPrice? {
        let dieselCodes: Set<String> = Self.dieselFuelCodes
        return (fuelPrice ?? [])
            .filter { dieselCodes.contains($0.fuelType) }
            .min { $0.price < $1.price }
    }

    /// HERE fuel-type codes that represent diesel for a truck driver:
    /// 1 = Diesel, 11 = Truck diesel, 46/48/50/55/62/63 = various
    /// premium diesel brand SKUs.
    static let dieselFuelCodes: Set<String> = ["1", "11", "46", "48", "50", "55", "62", "63"]
}

struct HerePosition: Decodable, Hashable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct HereFuelAddress: Decodable, Hashable {
    let city: String?
    let street: String?
    let streetNumber: String?
    let postalCode: String?
    let countryCode: String?
    let state: String?

    /// One-line presentation (street + city). Skips nils so a station
    /// with only a partial address still renders cleanly.
    var oneLine: String {
        var parts: [String] = []
        if let s = street {
            if let n = streetNumber { parts.append("\(s) \(n)") } else { parts.append(s) }
        }
        if let c = city { parts.append(c) }
        return parts.joined(separator: ", ")
    }
}

struct HereFuelPrice: Decodable, Hashable {
    let price: Double
    /// HERE fuel-type code as a string (the API returns numerics as
    /// string enums). See `HereFuelStation.dieselFuelCodes`.
    let fuelType: String
    let currency: String
    let lastUpdateTimestamp: String?
}

// MARK: - Client

/// Thin async wrapper around `GET /v3/stations`. Stateless;
/// the single `shared` instance is enough for the whole app.
final class HereFuelPricesClient {
    static let shared = HereFuelPricesClient()

    private let session: URLSession
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// `GET /v3/stations?prox=<lat>,<lng>,<radius>` — stations within
    /// `radiusMeters` of `center`, optionally filtered to a specific
    /// set of fuel-type codes.
    ///
    /// Defaults are tuned for a long-haul truck Home glance:
    /// 25 mi (~40 km) radius, diesel-family codes only, 20 results.
    func nearby(
        center: CLLocationCoordinate2D,
        radiusMeters: Int = 40_000,
        fuelTypes: [String] = Array(HereFuelStation.dieselFuelCodes)
    ) async throws -> [HereFuelStation] {
        var comps = URLComponents(string: "https://fuel.hereapi.com/v3/stations")!

        var items: [URLQueryItem] = [
            URLQueryItem(
                name: "prox",
                value: "\(center.latitude),\(center.longitude),\(radiusMeters)"
            )
        ]
        if !fuelTypes.isEmpty {
            items.append(URLQueryItem(name: "fuelType", value: fuelTypes.joined(separator: ",")))
        }
        comps.queryItems = items

        guard let url = comps.url else { throw HereMapsError.badURL }

        let data = try await authorizedData(for: url)
        do {
            return try decoder.decode(HereFuelStationsResponse.self, from: data).fuelStations
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }

    // MARK: - Bearer auth with 401 retry (mirrors HereRoutingClient)

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
