//
//  HereMatrixClient.swift
//  EusoTrip — REST client for HERE Matrix Routing API v8
//
//  Used by the dispatch board for many-to-many cost calculations:
//    "Given 10 available trucks and 15 pickup points, what's the cheapest
//    assignment?"
//
//  HERE supports both **sync** and **async** calls; sync caps at about
//  15×100 matrix cells, async supports up to a few thousand. EusoTrip uses
//  the sync path in-app (dispatch board fits 15×15 comfortably); large
//  fleet-wide optimizations should run server-side via the async API.
//
//  Endpoint (sync):
//    POST https://matrix.router.hereapi.com/v8/matrix?async=false
//
//  Auth: `Authorization: Bearer <token>` header (OAuth2 via
//  HEREAuthService). No apikey query string.
//
//  Body:
//    {
//      "origins":      [{"lat":32.44,"lng":-93.70}, ...],
//      "destinations": [{"lat":29.76,"lng":-95.37}, ...],
//      "regionDefinition": { "type": "world" },
//      "transportMode": "truck",
//      "matrixAttributes": ["travelTimes","distances"],
//      "vehicle": { ... from TruckProfile ... }
//    }
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

actor HereMatrixClient {

    static let shared = HereMatrixClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - Main call

    /// Computes a travel-time + distance matrix between origins and destinations.
    ///
    /// - Parameters:
    ///   - origins:       anywhere from 1 to ~15 points (sync limit).
    ///   - destinations:  same; matrix has `origins.count × destinations.count` cells.
    ///   - profile:       truck vehicle profile.
    ///   - departureTime: ISO-8601 timestamp. nil → depart now.
    /// - Returns: Matrix with travelTimes (seconds) and distances (meters),
    ///   both flat row-major arrays.
    func matrix(
        origins: [CLLocationCoordinate2D],
        destinations: [CLLocationCoordinate2D],
        profile: TruckProfile,
        departureTime: String? = nil
    ) async throws -> HereMatrixResponse {
        var comps = URLComponents(url: HereMapsConfig.matrixBaseURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "async",  value: "false"),
        ]

        guard let url = comps.url else { throw HereMapsError.badURL }

        let body = MatrixRequest(
            origins:          origins.map(Coord.init),
            destinations:     destinations.map(Coord.init),
            // Short local boards keep HERE's efficient autoCircle. Long-haul
            // boards switch to world because Matrix v8 hard-rejects
            // autoCircle regions above a 400 km diameter.
            regionDefinition: Self.regionDefinition(origins: origins, destinations: destinations),
            transportMode:    "truck",
            matrixAttributes: ["travelTimes", "distances"],
            departureTime:    departureTime,
            vehicle:          VehicleParams(profile: profile)
        )
        let bodyData = try encoder.encode(body)

        // RATE-LIMIT GATE: matrix is a Bearer-authenticated POST that
        // bypasses `HereBearerFetch`, so it pages through
        // `HereRateLimiter.shared` directly for the same paced slot +
        // deterministic 429 backoff. Only the fetch is gated; the JSON
        // decode below stays outside the slot.
        let lastRetryAfter = MatrixRetryAfterBox()
        let data = try await HereRateLimiter.shared.runData(
            retryAfterFor: { _ in lastRetryAfter.seconds }
        ) { [session, bodyData, url] in
            // Bearer-authenticated POST with a single 401 retry.
            func attempt() async throws -> (Data, HTTPURLResponse) {
                let token = try await HereMapsConfig.requireBearerToken()
                var req = URLRequest(url: url)
                req.timeoutInterval = 20  // app-wide no-lingering-load bound
                req.httpMethod = "POST"
                req.setValue("application/json",         forHTTPHeaderField: "Content-Type")
                req.setValue("Bearer \(token)",          forHTTPHeaderField: "Authorization")
                req.httpBody = bodyData
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
                if http.statusCode == 429 {
                    lastRetryAfter.seconds = HereRateLimiter.retryAfterSeconds(from: http)
                }
                let msg = String(data: data, encoding: .utf8) ?? ""
                throw HereMapsError.http(http.statusCode, msg)
            }
            return data
        }

        do {
            return try decoder.decode(HereMatrixResponse.self, from: data)
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }

    // MARK: - Request types

    private struct Coord: Encodable {
        let lat: Double
        let lng: Double
        init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lng = c.longitude }
    }
    private struct RegionDef: Encodable {
        let type: String
        var margin: Int? = nil
    }
    private struct MatrixRequest: Encodable {
        let origins: [Coord]
        let destinations: [Coord]
        let regionDefinition: RegionDef
        let transportMode: String
        let matrixAttributes: [String]
        let departureTime: String?
        let vehicle: VehicleParams
    }
    /// Matrix API takes vehicle params as a nested JSON object (unlike Routing
    /// v8 which uses repeated `vehicle[field]=value` GET params).
    private struct VehicleParams: Encodable {
        let grossWeight: Int?
        let weightPerAxle: Int?
        let height: Int?
        let width: Int?
        let length: Int?
        let axleCount: Int?
        let trailerCount: Int?
        // 2026-06-03 — removed `type` + `emissionType`: invalid in Matrix v8
        // vehicle schema (type allows only straightTruck/tractor; there is no
        // emissionType field) → every POST 400'd → empty candidates strip.
        let tunnelCategory: String?
        let shippedHazardousGoods: [String]?

        init(profile: TruckProfile) {
            grossWeight           = profile.grossWeightKg
            weightPerAxle         = profile.weightPerAxleKg
            height                = profile.heightCm
            width                 = profile.widthCm
            length                = profile.lengthCm
            axleCount             = profile.axleCount
            trailerCount          = profile.trailerCount
            tunnelCategory        = profile.tunnelCategory?.hereValue
            shippedHazardousGoods = profile.shippedHazardousGoods.isEmpty
                ? nil
                : profile.shippedHazardousGoods.map(\.hereValue).sorted()
        }
    }

    private static func regionDefinition(
        origins: [CLLocationCoordinate2D],
        destinations: [CLLocationCoordinate2D]
    ) -> RegionDef {
        let points = (origins + destinations).filter { c in
            c.latitude.isFinite && c.longitude.isFinite &&
            abs(c.latitude) <= 90 && abs(c.longitude) <= 180 &&
            !(c.latitude == 0 && c.longitude == 0)
        }
        var maxMeters: CLLocationDistance = 0
        for i in points.indices {
            for j in points.indices where j > i {
                maxMeters = max(maxMeters, haversineMeters(points[i], points[j]))
            }
        }
        return maxMeters <= 380_000
            ? RegionDef(type: "autoCircle", margin: 10_000)
            : RegionDef(type: "world")
    }

    private static func haversineMeters(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let radius = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = pow(sin(dLat / 2), 2) +
            cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2)
        return 2 * radius * asin(sqrt(h))
    }
}

/// Carries a 429 `Retry-After` out of one gated matrix POST into the
/// limiter's backoff hook. Confined to a single `runData` call.
private final class MatrixRetryAfterBox: @unchecked Sendable {
    var seconds: TimeInterval?
}
