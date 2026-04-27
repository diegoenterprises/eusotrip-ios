//
//  HereRoutingClient.swift
//  EusoTrip — REST client for HERE Routing API v8 (truck-aware)
//
//  Endpoint:
//    GET https://router.hereapi.com/v8/routes
//
//  Minimum params:
//    - transportMode=truck
//    - origin=lat,lng
//    - destination=lat,lng
//    - return=polyline,summary,actions
//
//  Auth: `Authorization: Bearer <token>` header (OAuth2 client-credentials
//  via HEREAuthService). No apikey query string.
//
//  Plus every field from TruckProfile.asRoutingQueryItems() (weight / axles /
//  hazmat / tunnel category).
//
//  Docs: https://developer.here.com/documentation/routing-api/api-reference-swagger.html
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

/// Sequence of stops for a multi-leg route. The first is the origin, the last is
/// the destination; anything in between is a via-point (HERE param `via=`).
struct HereStops {
    let origin: CLLocationCoordinate2D
    let via: [CLLocationCoordinate2D]
    let destination: CLLocationCoordinate2D

    init(origin: CLLocationCoordinate2D,
         via: [CLLocationCoordinate2D] = [],
         destination: CLLocationCoordinate2D) {
        self.origin = origin
        self.via = via
        self.destination = destination
    }

    /// Convenience: two-stop (pickup → delivery).
    static func pickupToDelivery(pickup: LoadLocation?, delivery: LoadLocation?) -> HereStops? {
        guard let p = pickup, let d = delivery else { return nil }
        return HereStops(
            origin:      CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng),
            destination: CLLocationCoordinate2D(latitude: d.lat, longitude: d.lng)
        )
    }
}

/// Options that HERE Routing v8 exposes but which aren't part of the vehicle profile.
struct HereRoutingOptions {
    /// ISO-8601 (e.g. "2026-04-18T09:00:00-04:00"). Nil = depart now.
    var departureTime: String? = nil
    /// Fields to include. `polyline,summary,actions` is the typical set for
    /// a driver-nav use case; add `spans,tolls,incidents` for richer detail.
    var returnFields: [String] = ["polyline", "summary", "actions", "spans", "tolls", "notices"]
    /// Span columns to return — only respected when `returnFields` contains "spans".
    var spanFields: [String] = ["names", "speedLimit", "countryCode", "functionalClass", "truckAttributes"]
    /// Number of alternative routes to compute (0–6). HERE's default is 0.
    var alternatives: Int = 0
    /// Language for action narration ("en-US", "es-MX", etc).
    var language: String? = "en-US"
    /// Whether to avoid features. HERE accepts a comma-separated list of:
    /// tollRoad, controlledAccessHighway, ferry, tunnel, dirtRoad, difficultTurns.
    var avoidFeatures: [String] = []
}

// MARK: - Client

actor HereRoutingClient {

    static let shared = HereRoutingClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Main call

    /// Computes a truck-aware route via HERE Routing v8.
    func route(
        stops: HereStops,
        profile: TruckProfile,
        options: HereRoutingOptions = HereRoutingOptions()
    ) async throws -> HereRoutesResponse {
        var comps = URLComponents(url: HereMapsConfig.routingBaseURL, resolvingAgainstBaseURL: false)!

        var items: [URLQueryItem] = [
            URLQueryItem(name: "transportMode",    value: "truck"),
            URLQueryItem(name: "origin",           value: Self.fmt(stops.origin)),
            URLQueryItem(name: "destination",      value: Self.fmt(stops.destination)),
            URLQueryItem(name: "return",           value: options.returnFields.joined(separator: ",")),
        ]

        if options.returnFields.contains("spans") {
            items.append(URLQueryItem(name: "spans", value: options.spanFields.joined(separator: ",")))
        }

        for v in stops.via {
            items.append(URLQueryItem(name: "via", value: Self.fmt(v)))
        }

        if let dep = options.departureTime {
            items.append(URLQueryItem(name: "departureTime", value: dep))
        }
        if options.alternatives > 0 {
            items.append(URLQueryItem(name: "alternatives", value: String(options.alternatives)))
        }
        if let lang = options.language {
            items.append(URLQueryItem(name: "lang", value: lang))
        }
        if !options.avoidFeatures.isEmpty {
            items.append(URLQueryItem(name: "avoid[features]",
                                      value: options.avoidFeatures.joined(separator: ",")))
        }

        items += profile.asRoutingQueryItems()

        comps.queryItems = items

        guard let url = comps.url else { throw HereMapsError.badURL }

        // Bearer-authenticated fetch with a single 401 retry: if the
        // cached token was revoked mid-session, drop it and re-exchange
        // once before surfacing the error.
        let data = try await authorizedData(for: url)
        do {
            return try decoder.decode(HereRoutesResponse.self, from: data)
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }

    /// GET `url` with `Authorization: Bearer <token>`. On HTTP 401, invalidate
    /// the cached token and retry exactly once. Throws `HereMapsError.http`
    /// for any non-2xx response after the retry.
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

    /// Convenience: computes a route for a Load (pickup → delivery) using a
    /// TruckProfile derived from that Load.
    func route(for load: Load,
               baseEquipment: TruckProfile = .standardUSSemiLoaded,
               options: HereRoutingOptions = HereRoutingOptions()) async throws -> HereRoutesResponse {
        guard let stops = HereStops.pickupToDelivery(pickup: load.pickupLocation,
                                                     delivery: load.deliveryLocation) else {
            throw HereMapsError.providerError("Load is missing pickup or delivery coordinates.")
        }
        let profile = TruckProfile.from(load: load, baseEquipment: baseEquipment)
        return try await route(stops: stops, profile: profile, options: options)
    }

    // MARK: - Helpers

    /// HERE expects "lat,lng" to 7 decimal places.
    static func fmt(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.7f,%.7f", c.latitude, c.longitude)
    }

    /// Decodes the `polyline` field on each section into `[CLLocationCoordinate2D]`.
    static func polyline(for section: HereRouteSection) -> [CLLocationCoordinate2D] {
        HereFlexiblePolyline.decode(section.polyline)
    }

    /// Flattens a full route's polyline across all its sections.
    static func polyline(for route: HereRoute) -> [CLLocationCoordinate2D] {
        route.sections.flatMap { polyline(for: $0) }
    }
}
