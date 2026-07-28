//
//  HereFuelPricesClient.swift
//  EusoTrip — authenticated backend client for HERE Fuel Prices API v3.
//
//  Endpoint:
//      GET https://fuel.hereapi.com/v3/stations
//
//  Required params (2026-06 schema — `prox` was retired):
//      - in=circle:<lat>,<lng>;r=<radius-meters>
//      - apiKey=<KEY>    OR    Authorization: Bearer <token>
//
//  Optional params used here:
//      - fuelType=1,11,55  — diesel-family codes (truck driver app).
//                            Omit to return every fuel type at each
//                            station.
//
//  Provider credentials stay on the EusoTrip server. The app calls the typed
//  `hereMaps.fuelPricesNearby` procedure. When HERE cannot answer, callers
//  receive an honest empty set; no station or price is synthesized.
//
//  Docs: https://docs.here.com/fuel-prices/docs/
//        Fuel type codes: https://docs.here.com/fuel-prices/docs/fuel-types-mapping
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

// MARK: - Response wire types

/// Raw decoded shape of `GET /v3/stations`.
///
/// 2026-06-09 wire-shape drift (live-probed on the enterprise key —
/// the old names were silently killing this decode, which the fail-soft
/// add-on layer masked as "no fuel pins"):
///   top-level `fuelStations` → `stations`
///   station `fuelPrice`      → `prices`
///   station/price `lastUpdateTimestamp` → `modified`
///   address `streetNumber`   → `houseNumber`
///   position `latitude/longitude` → `lat/lng`
/// Swift property names stay stable for the 8 consumer screens;
/// `CodingKeys` absorb the rename.
struct HereFuelStationsResponse: Decodable {
    let fuelStations: [HereFuelStation]

    private enum CodingKeys: String, CodingKey {
        case fuelStations = "stations"
    }
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

    private enum CodingKeys: String, CodingKey {
        case id, name, brand, brandIcon, position, address, distance, open24x7
        case fuelPrice = "prices"
        case lastUpdateTimestamp = "modified"
    }

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

/// Shared position wire type for the Fuel v3 + Browse-backed clients
/// (EV / parking / safety cameras). HERE is split-brained on this:
/// Browse and Fuel v3 send `{lat, lng}`, older products send
/// `{latitude, longitude}`. Decoding ONLY the long names silently
/// zeroed every Browse-backed add-on layer (keyNotFound swallowed by
/// the fail-soft fetchers) — so this decoder accepts BOTH spellings.
struct HerePosition: Decodable, Hashable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude, lat, lng
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let la = try c.decodeIfPresent(Double.self, forKey: .latitude),
           let lo = try c.decodeIfPresent(Double.self, forKey: .longitude) {
            latitude = la
            longitude = lo
        } else {
            latitude = try c.decode(Double.self, forKey: .lat)
            longitude = try c.decode(Double.self, forKey: .lng)
        }
    }

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

    private enum CodingKeys: String, CodingKey {
        case city, street, postalCode, countryCode, state
        case streetNumber = "houseNumber"
    }

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

    private enum CodingKeys: String, CodingKey {
        case price, fuelType, currency
        case lastUpdateTimestamp = "modified"
    }
}

// MARK: - Client

/// Thin async wrapper around `GET /v3/stations`. Stateless;
/// the single `shared` instance is enough for the whole app.
final class HereFuelPricesClient {
    static let shared = HereFuelPricesClient()

    init(session: URLSession = .shared) {
        _ = session
    }

    /// `GET /v3/stations?in=circle:<lat>,<lng>;r=<radius>` — stations
    /// within `radiusMeters` of `center`, optionally filtered to a
    /// specific set of fuel-type codes.
    ///
    /// 2026-06-09: HERE made `in=` MANDATORY on Fuel Prices v3 — the
    /// older `prox=lat,lng,radius` shape now 400s with `E612015`
    /// "Mandatory parameter 'in' is missing" (live-probed: `in=circle:`
    /// returns real stations on the enterprise key). Same circle
    /// semantics, new spelling.
    ///
    /// Defaults are tuned for a long-haul truck Home glance:
    /// 25 mi (~40 km) radius, diesel-family codes only, 20 results.
    func nearby(
        center: CLLocationCoordinate2D,
        radiusMeters: Int = 40_000,
        fuelTypes: [String] = Array(HereFuelStation.dieselFuelCodes)
    ) async throws -> [HereFuelStation] {
        let rows: [BackendStation] = try await EusoTripAPI.shared.query(
            "hereMaps.fuelPricesNearby",
            input: BackendRequest(
                at: BackendCoord(lat: center.latitude, lng: center.longitude),
                radiusMeters: min(200_000, max(500, radiusMeters)),
                fuelTypes: Self.backendFuelTypes(fuelTypes)
            )
        )
        return rows.compactMap(\.nativeStation)
    }

    private static func backendFuelTypes(_ codes: [String]) -> [String]? {
        guard !codes.isEmpty else { return nil }
        var types = Set<String>()
        if !Set(codes).isDisjoint(with: HereFuelStation.dieselFuelCodes) {
            types.insert("diesel")
        }
        if codes.contains(where: { ["2", "3", "4"].contains($0) }) {
            types.insert("gasoline")
        }
        if codes.contains("5") { types.insert("e85") }
        return types.isEmpty ? ["diesel"] : types.sorted()
    }

    private struct BackendCoord: Encodable {
        let lat: Double
        let lng: Double
    }

    private struct BackendRequest: Encodable {
        let at: BackendCoord
        let radiusMeters: Int
        let fuelTypes: [String]?
    }

    private struct BackendStation: Decodable {
        let id: String
        let brand: String?
        let name: String
        let address: String?
        let lat: Double
        let lng: Double
        let distanceMeters: Int?
        let dieselPrice: Double?
        let currency: String
        let updatedAt: String?
        let raw: HereFuelStation?

        var nativeStation: HereFuelStation? {
            if let raw, HereGeocodingClient.isSane(
                raw.position.latitude,
                raw.position.longitude
            ) {
                return raw
            }
            guard HereGeocodingClient.isSane(lat, lng) else { return nil }
            let prices = dieselPrice.map {
                [HereFuelPrice(
                    price: $0,
                    fuelType: "1",
                    currency: currency,
                    lastUpdateTimestamp: updatedAt
                )]
            }
            return HereFuelStation(
                id: id,
                name: name,
                brand: brand,
                brandIcon: nil,
                position: HerePosition(latitude: lat, longitude: lng),
                address: address.map {
                    HereFuelAddress(
                        city: nil,
                        street: $0,
                        streetNumber: nil,
                        postalCode: nil,
                        countryCode: nil,
                        state: nil
                    )
                },
                distance: distanceMeters,
                open24x7: nil,
                fuelPrice: prices,
                lastUpdateTimestamp: updatedAt
            )
        }
    }
}
