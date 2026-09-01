//
//  HereRoutingClient.swift
//  EusoTrip — authenticated backend client for HERE Routing API v8
//
//  Provider credentials stay on the EusoTrip server. The app calls the typed
//  `hereMaps.route` tRPC procedure and decodes the preserved HERE v8 payload.
//
//  Minimum params:
//    - transportMode=truck
//    - origin=lat,lng
//    - destination=lat,lng
//    - return=polyline,summary,actions,tolls
//    - spans=maxSpeed,functionalClass,truckAttributes (separate param; not a
//      `return` value)
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
        guard
            let p = pickup,
            let d = delivery,
            let pickupCoordinate = LatLongParser.validatedCoordinate(
                latitude: p.lat,
                longitude: p.lng
            ),
            let deliveryCoordinate = LatLongParser.validatedCoordinate(
                latitude: d.lat,
                longitude: d.lng
            )
        else { return nil }
        return HereStops(
            origin: pickupCoordinate,
            destination: deliveryCoordinate
        )
    }
}

/// Options that HERE Routing v8 exposes but which aren't part of the vehicle profile.
struct HereRoutingOptions {
    /// ISO-8601 (e.g. "2026-04-18T09:00:00-04:00"). Nil = depart now.
    var departureTime: String? = nil
    /// Fields to include in HERE Routing v8 `return`.
    ///
    /// Live verification on 2026-06-21 corrected an earlier false premise:
    /// `spans` is NOT a return type (`return=...,spans` returns HTTP 400).
    /// It must be sent as its own query param while `polyline` is present.
    /// `tolls` is a valid return type and feeds lane economics.
    ///
    /// `notices` remains intentionally absent: HERE emits notices when present
    /// but rejects `notices` as an explicit `return` value.
    var returnFields: [String] = ["polyline", "summary", "actions", "tolls"]
    /// Span columns used by route-weather and road-intelligence sampling.
    /// `speedLimit` is deprecated by HERE; `maxSpeed` is the verified v8 field.
    var spanFields: [String] = ["maxSpeed", "functionalClass", "truckAttributes"]
    /// Number of alternative routes to compute (0–6). HERE's default is 0.
    var alternatives: Int = 0
    /// Language for action narration ("en-US", "es-MX", etc).
    var language: String? = "en-US"
    /// Whether to avoid features. HERE accepts a comma-separated list of:
    /// tollRoad, controlledAccessHighway, ferry, tunnel, dirtRoad, difficultTurns.
    var avoidFeatures: [String] = []
    /// Weather/flood hazards to route around (HERE Routing v8 `avoid[areas]`,
    /// truck only). Each transforms into a bbox / polygon / corridor spec.
    /// Empty = no hazard reroute. See `HereAvoidArea`.
    var avoidAreas: [HereAvoidArea] = []
}

// MARK: - Avoid areas (weather-hazard reroute)

/// A geographic hazard the TRUCK route should steer around — a NWS CAP
/// polygon, a simplified WeatherKit severe cell, a USGS flood reach. Becomes a
/// HERE Routing v8 `avoid[areas]` spec (bbox / polygon / corridor). This is the
/// "one missing primitive" the symbiotic loop needs: without it a weather cell
/// can't become a routed detour, only a synthetic +15%-miles estimate.
///
/// TRUCK ONLY — rail/vessel have no HERE router, so a hazard there is
/// advise/hold, never an auto-reroute.
enum HereAvoidArea {
    /// Coarse rectangle (a low-res cell). HERE: `bbox:{west},{south},{east},{north}`.
    case bbox(west: Double, south: Double, east: Double, north: Double)
    /// A hazard outline (NWS CAP / simplified WeatherKit cell). HERE:
    /// `polygon:{lat},{lng};…` — auto-simplified + capped to HERE's vertex limit.
    case polygon([CLLocationCoordinate2D])
    /// A linear hazard (USGS flood reach). HERE: `corridor:{flexiblePolyline};r={m}`.
    case corridor(path: [CLLocationCoordinate2D], radiusMeters: Int)

    /// HERE caps polygon vertices; stay well under and simplify down to it.
    static let maxVertices = 20

    /// The HERE v8 `avoid[areas]` spec, or nil if degenerate.
    func spec() -> String? {
        switch self {
        case let .bbox(w, s, e, n):
            guard e > w, n > s else { return nil }
            return "bbox:\(w),\(s),\(e),\(n)"
        case let .polygon(pts):
            let simplified = Self.cap(Self.simplify(pts), to: Self.maxVertices)
            guard simplified.count >= 3 else {
                return Self.boundingBox(of: pts)?.spec()   // degenerate → fall back to bbox
            }
            let body = simplified
                .map { "\($0.latitude),\($0.longitude)" }
                .joined(separator: ";")
            return "polygon:\(body)"
        case let .corridor(path, radius):
            guard path.count >= 2, radius > 0 else { return nil }
            let encoded = HereFlexiblePolyline.encode(Self.cap(Self.simplify(path), to: Self.maxVertices))
            guard !encoded.isEmpty else { return nil }
            return "corridor:\(encoded);r=\(radius)"
        }
    }

    /// Bounding box of a coordinate set — the coarse avoid fallback.
    static func boundingBox(of pts: [CLLocationCoordinate2D]) -> HereAvoidArea? {
        guard let first = pts.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for c in pts {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        guard maxLat > minLat, maxLng > minLng else { return nil }
        return .bbox(west: minLng, south: minLat, east: maxLng, north: maxLat)
    }

    // MARK: simplification

    /// Ramer–Douglas–Peucker simplification (epsilon in degrees) — the
    /// symbiotic design reduces hazard cells before handing them to HERE.
    static func simplify(_ pts: [CLLocationCoordinate2D], epsilon: Double = 0.01) -> [CLLocationCoordinate2D] {
        guard pts.count > 2 else { return pts }
        var maxDist = 0.0
        var idx = 0
        let start = pts.first!
        let end = pts.last!
        for i in 1..<(pts.count - 1) {
            let d = perpDistance(pts[i], start, end)
            if d > maxDist { maxDist = d; idx = i }
        }
        if maxDist > epsilon {
            let left = simplify(Array(pts[0...idx]), epsilon: epsilon)
            let right = simplify(Array(pts[idx...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [start, end]
    }

    private static func perpDistance(_ p: CLLocationCoordinate2D,
                                     _ a: CLLocationCoordinate2D,
                                     _ b: CLLocationCoordinate2D) -> Double {
        let dx = b.longitude - a.longitude
        let dy = b.latitude - a.latitude
        let mag = (dx * dx + dy * dy).squareRoot()
        guard mag > 0 else {
            return ((p.longitude - a.longitude) * (p.longitude - a.longitude)
                    + (p.latitude - a.latitude) * (p.latitude - a.latitude)).squareRoot()
        }
        let u = ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) / (mag * mag)
        let cx = a.longitude + u * dx
        let cy = a.latitude + u * dy
        return ((p.longitude - cx) * (p.longitude - cx) + (p.latitude - cy) * (p.latitude - cy)).squareRoot()
    }

    /// Cap vertex count by uniform decimation (endpoints preserved).
    static func cap(_ pts: [CLLocationCoordinate2D], to maxCount: Int) -> [CLLocationCoordinate2D] {
        guard pts.count > maxCount, maxCount >= 2 else { return pts }
        let step = Double(pts.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { pts[Int((Double($0) * step).rounded())] }
    }
}

// MARK: - Client

actor HereRoutingClient {

    static let shared = HereRoutingClient()

    init(session: URLSession = .shared) {
        // Keep the injectable signature source-compatible with existing tests.
        // Network transport is owned by EusoTripAPI so auth/session refresh and
        // provider credentials remain centralized.
        _ = session
    }

    // MARK: - Main call

    /// Computes a truck-aware route via HERE Routing v8.
    func route(
        stops: HereStops,
        profile: TruckProfile,
        options: HereRoutingOptions = HereRoutingOptions()
    ) async throws -> HereRoutesResponse {
        let response: BackendResponse = try await EusoTripAPI.shared.query(
            "hereMaps.route",
            input: BackendRequest(
                origin: BackendCoord(stops.origin),
                destination: BackendCoord(stops.destination),
                via: stops.via.isEmpty ? nil : stops.via.map(BackendCoord.init),
                transportMode: "truck",
                truck: BackendTruck(profile),
                avoid: Self.backendAvoidFeatures(options.avoidFeatures),
                avoidAreas: options.avoidAreas.isEmpty
                    ? nil
                    : options.avoidAreas.compactMap(BackendAvoidArea.init),
                departureTime: options.departureTime,
                alternatives: options.alternatives > 0 ? options.alternatives : nil,
                lang: options.language,
                returnPolyline: options.returnFields.contains("polyline")
            )
        )
        guard response.ok, let raw = response.raw, !raw.routes.isEmpty else {
            throw HereMapsError.providerError(
                response.error ?? response.summary ?? "HERE returned no route."
            )
        }
        return raw
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

    /// HERE accepts decimal coordinates. Keep Swift's round-trippable Double
    /// representation so a precise user/provider fix is not truncated here.
    static func fmt(_ c: CLLocationCoordinate2D) -> String {
        "\(c.latitude),\(c.longitude)"
    }

    /// Decodes the `polyline` field on each section into `[CLLocationCoordinate2D]`.
    static func polyline(for section: HereRouteSection) -> [CLLocationCoordinate2D] {
        HereFlexiblePolyline.decode(section.polyline)
    }

    /// Flattens a full route's polyline across all its sections.
    static func polyline(for route: HereRoute) -> [CLLocationCoordinate2D] {
        route.sections.flatMap { polyline(for: $0) }
    }

    private static func backendAvoidFeatures(_ values: [String]) -> [String]? {
        let supported = Set([
            "tollRoad",
            "controlledAccessHighway",
            "ferry",
            "tunnel",
            "dirtRoad",
            "difficultTurns",
        ])
        let normalized = values.compactMap { value -> String? in
            if value == "motorway" { return "controlledAccessHighway" }
            return supported.contains(value) ? value : nil
        }
        return normalized.isEmpty ? nil : Array(Set(normalized)).sorted()
    }

    private struct BackendCoord: Encodable {
        let lat: Double
        let lng: Double

        init(_ coordinate: CLLocationCoordinate2D) {
            lat = coordinate.latitude
            lng = coordinate.longitude
        }
    }

    private struct BackendTruck: Encodable {
        let grossWeightKg: Int?
        let weightPerAxleKg: Int?
        let heightCm: Int?
        let widthCm: Int?
        let lengthCm: Int?
        let axleCount: Int?
        let trailerCount: Int?
        let shippedHazardousGoods: [String]?
        let tunnelCategory: String?

        init(_ profile: TruckProfile) {
            grossWeightKg = profile.grossWeightKg
            weightPerAxleKg = profile.weightPerAxleKg
            heightCm = profile.heightCm
            widthCm = profile.widthCm
            lengthCm = profile.lengthCm
            axleCount = profile.axleCount
            trailerCount = profile.trailerCount
            let goods = profile.shippedHazardousGoods.map { good in
                good == .radioactive ? "radioActive" : good.hereValue
            }.sorted()
            shippedHazardousGoods = goods.isEmpty ? nil : goods
            tunnelCategory = profile.tunnelCategory?.hereValue
        }
    }

    private struct BackendAvoidArea: Encodable {
        let kind: String
        let west: Double?
        let south: Double?
        let east: Double?
        let north: Double?
        let points: [BackendCoord]?
        let path: [BackendCoord]?
        let radiusMeters: Int?

        init?(_ area: HereAvoidArea) {
            switch area {
            case let .bbox(west, south, east, north):
                guard east > west, north > south else { return nil }
                kind = "bbox"
                self.west = west
                self.south = south
                self.east = east
                self.north = north
                points = nil
                path = nil
                radiusMeters = nil
            case let .polygon(coordinates):
                let coordinates = HereAvoidArea.cap(
                    HereAvoidArea.simplify(coordinates),
                    to: HereAvoidArea.maxVertices
                )
                guard coordinates.count >= 3 else { return nil }
                kind = "polygon"
                west = nil
                south = nil
                east = nil
                north = nil
                points = coordinates.map(BackendCoord.init)
                path = nil
                radiusMeters = nil
            case let .corridor(coordinates, radius):
                let coordinates = HereAvoidArea.cap(
                    HereAvoidArea.simplify(coordinates),
                    to: HereAvoidArea.maxVertices
                )
                guard coordinates.count >= 2, radius >= 25 else { return nil }
                kind = "corridor"
                west = nil
                south = nil
                east = nil
                north = nil
                points = nil
                path = coordinates.map(BackendCoord.init)
                radiusMeters = radius
            }
        }
    }

    private struct BackendRequest: Encodable {
        let origin: BackendCoord
        let destination: BackendCoord
        let via: [BackendCoord]?
        let transportMode: String
        let truck: BackendTruck
        let avoid: [String]?
        let avoidAreas: [BackendAvoidArea]?
        let departureTime: String?
        let alternatives: Int?
        let lang: String?
        let returnPolyline: Bool
    }

    private struct BackendResponse: Decodable {
        let ok: Bool
        let summary: String?
        let error: String?
        let raw: HereRoutesResponse?
    }
}
