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
    /// Fields to include. The richer set is RE-ENABLED on enterprise per
    /// HERE_ENTERPRISE_AUDIT (2026-06-14) action #3.
    ///
    /// History: 2026-05-17 the BASIC deployment rejected the extras
    /// (TestFlight 262: "Invalid return type at 'spans'"), so they were
    /// dropped to `polyline,summary,actions`. Enterprise accepts them, and
    /// the symbiotic weather loop REQUIRES them:
    ///   • `spans`   — per-segment on-road geometry, so weather can be
    ///                 sampled along the route at the ETA-matched points
    ///                 (Pillar 3, the route-weather timeline).
    ///   • `notices` — the forced-pass-through signal ("no avoidance route —
    ///                 the path crosses the hazard"), the honesty primitive
    ///                 that distinguishes "rerouted" from "routed through the
    ///                 storm anyway" (Pillar 1).
    ///   • `tolls`   — toll-aware lane cost.
    ///
    /// Safe to ship: the raw-bracket `percentEncodedQuery` path that crashed
    /// (EXC_BREAKPOINT, TestFlight 259) was already reverted to the
    /// `queryItems` path, so a stray field rejection now surfaces as a soft
    /// `HereMapsError.http` (caller serves last-good route state) — never a
    /// crash. If the enterprise deployment ever rejects one, trim just that
    /// field; the `if returnFields.contains("spans")` plumbing below already
    /// emits the `spans=` columns.
    ///
    /// REVERTED 2026-06-17: `notices` is NOT a valid HERE v8 `return` value
    /// (notices auto-appear in the response when present) — including it makes
    /// HERE reject the whole `return` param → "no route" (confirmed in prod on
    /// the server, fixed in PR #94). Back to the known-good three. `spans`
    /// (route-weather sampling) + `tolls` get re-added here when the weather
    /// sampler needs them — each CURL-VALIDATED against the enterprise key
    /// first, per the audit's own rule (the step I skipped).
    var returnFields: [String] = ["polyline", "summary", "actions"]
    /// Span columns — kept for future re-enablement; not currently
    /// used because `spans` was dropped from returnFields.
    var spanFields: [String] = ["names", "speedLimit", "countryCode", "functionalClass", "truckAttributes"]
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
            return String(format: "bbox:%.6f,%.6f,%.6f,%.6f", w, s, e, n)
        case let .polygon(pts):
            let simplified = Self.cap(Self.simplify(pts), to: Self.maxVertices)
            guard simplified.count >= 3 else {
                return Self.boundingBox(of: pts)?.spec()   // degenerate → fall back to bbox
            }
            let body = simplified.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }.joined(separator: ";")
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
        // Weather-hazard reroute: each hazard → a bbox/polygon/corridor spec,
        // pipe-separated. The reroute loop drops these in so HERE actually
        // routes the truck AROUND the cell instead of estimating a synthetic
        // +15% miles — the one missing primitive in the symbiotic loop.
        let areaSpecs = options.avoidAreas.compactMap { $0.spec() }
        if !areaSpecs.isEmpty {
            items.append(URLQueryItem(name: "avoid[areas]",
                                      value: areaSpecs.joined(separator: "|")))
        }

        items += profile.asRoutingQueryItems()

        // HERE Routing v8 accepts percent-encoded `%5B`/`%5D` for
        // bracket params — confirmed by re-reading 2026-05-16
        // logs: the original "Malformed request · Error while
        // parsing" rejections were caused by two bad VALUES
        // (`vehicle[type]=semiTrailer` not in the v8 enum, and
        // `vehicle[emissionType]=epa` not in the euro1–6 enum),
        // NOT by bracket encoding. Both bad fields are now dropped
        // in `TruckProfile.asRoutingQueryItems()`.
        //
        // Earlier in-flight 2026-05-17 attempt used
        // `URLComponents.percentEncodedQuery` with raw brackets to
        // preserve them — that crashed TestFlight 259 with
        // EXC_BREAKPOINT (the setter fatalErrors on RFC-3986-invalid
        // chars). Reverted to the simple, proven `queryItems` path.
        var comps = URLComponents(url: HereMapsConfig.routingBaseURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = items
        guard let url = comps.url else { throw HereMapsError.badURL }

        // Bearer-authenticated fetch with a single 401 retry: if the
        // cached token was revoked mid-session, drop it and re-exchange
        // once before surfacing the error.
        let data: Data
        do {
            data = try await authorizedData(for: url)
        } catch {
            // Founder-flagged 2026-05-17: surface the full failing URL
            // to the console so the next round of HERE-rejection
            // debugging doesn't require re-instrumenting. Only fires
            // in DEBUG so we don't leak Bearer tokens (URL has none —
            // token rides in the Authorization header — but keeping
            // the gate in case the contract changes).
            #if DEBUG
            print("[HereRouting] request failed for url=\(url.absoluteString) — \(error)")
            #endif
            throw error
        }
        do {
            return try decoder.decode(HereRoutesResponse.self, from: data)
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }

    /// GET `url` with `Authorization: Bearer <token>`. On HTTP 401, invalidate
    /// the cached token and retry exactly once. Throws `HereMapsError.http`
    /// for any non-2xx response after the retry.
    ///
    /// RATE-LIMIT GATE: routing bypasses `HereBearerFetch` (it has its
    /// own 401 recipe), so it pages through `HereRateLimiter.shared`
    /// directly — same paced slot + deterministic 429 backoff/cooldown
    /// as every other HERE call. After the backoff budget is spent the
    /// 429 surfaces and the caller serves last-good route state.
    private func authorizedData(for url: URL) async throws -> Data {
        let lastRetryAfter = RoutingRetryAfterBox()

        return try await HereRateLimiter.shared.runData(
            retryAfterFor: { _ in lastRetryAfter.seconds }
        ) { [session] in
            func attempt() async throws -> (Data, HTTPURLResponse) {
                let token = try await HereMapsConfig.requireBearerToken()
                var req = URLRequest(url: url)
                req.timeoutInterval = 20  // app-wide no-lingering-load bound
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
                if http.statusCode == 429 {
                    lastRetryAfter.seconds = HereRateLimiter.retryAfterSeconds(from: http)
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                throw HereMapsError.http(http.statusCode, body)
            }
            return data
        }
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

/// Carries a 429 `Retry-After` out of one gated routing fetch into the
/// limiter's backoff hook. Confined to a single `runData` call, hence
/// `@unchecked Sendable`.
private final class RoutingRetryAfterBox: @unchecked Sendable {
    var seconds: TimeInterval?
}
