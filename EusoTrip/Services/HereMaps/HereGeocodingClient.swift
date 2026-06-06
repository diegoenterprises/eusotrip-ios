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

    // MARK: - Confirming resolve (lock real coords to the chosen place)

    /// The outcome of confirming a picked suggestion: the true coordinate
    /// plus a clean label derived from the resolved structured address.
    struct ResolvedPlace {
        let coordinate: CLLocationCoordinate2D
        /// "<street/POI>, City, ST" rebuilt from admin fields — never HERE's
        /// raw, sometimes-malformed `title` ("Barbour Ct, San Pedro, CA" /
        /// "Part near (of) …").
        let label: String
        /// The structured hit we locked onto (city/state/country available).
        let item: HereGeocodeItem
    }

    /// Confirm a chosen autosuggest hit into a true coordinate + clean label
    /// using an ADMIN-AWARE policy, because HERE's behaviour splits in two:
    ///
    ///   • A bare POI / port hit ("Port of Houston-Barbours Cut Terminal")
    ///     usually carries the CORRECT ride-along coordinate but NO admin
    ///     (city == nil, state == nil). Forward-geocoding that bare title is
    ///     UNRELIABLE — unbiased it lands on a same-named place on the wrong
    ///     coast ("Barbour Ct, San Pedro CA", 1,394 mi off). So for a bare
    ///     POI we TRUST the hit's own coordinate and only reverse-geocode it
    ///     for a clean "City, ST" label — we never re-geocode the title.
    ///
    ///   • An admin-anchored hit ("Terminal Island, Los Angeles, CA")
    ///     carries city+state. We forward-geocode the admin-anchored title and
    ///     keep the result whose city+state matches the hit — but behind a
    ///     HARD SANITY GATE: the chosen result must be within 100 mi of the
    ///     hit's own coordinate, else HERE mis-resolved and we keep the hit
    ///     coord. We never blind-accept `results.first`.
    ///
    ///   • A coordless / categorical hit has no coordinate to trust, so it's
    ///     forward-geocoded and must produce an admin match or a single
    ///     dominant result; otherwise we return nil and let the caller keep
    ///     the typed text without bogus coords.
    func resolve(_ hit: HereGeocodeItem) async -> ResolvedPlace? {
        // ── Case 1: the hit carries a sane, usable coordinate. ──────────────
        if let pos = hit.position, Self.isSane(pos.lat, pos.lng) {
            let hitCoord = CLLocationCoordinate2D(latitude: pos.lat, longitude: pos.lng)

            if hit.hasExplicitAdmin {
                // 1b) HAS admin — anchor the forward geocode on the admin-
                //     bearing title, require an admin match, and gate it to
                //     within 100 mi of the hit's own coordinate.
                let confirmed = (try? await geocode(query: hit.title, near: nil, limit: 5)) ?? []
                if let chosen = pickBestMatch(for: hit, among: confirmed),
                   let cpos = chosen.position,
                   Self.greatCircleMiles(pos.lat, pos.lng, cpos.lat, cpos.lng) <= 100 {
                    return ResolvedPlace(
                        coordinate: CLLocationCoordinate2D(latitude: cpos.lat, longitude: cpos.lng),
                        label: chosen.displayLabel,
                        item: chosen
                    )
                }
                // Forward geocode produced no admin match within 100 mi (or
                // none at all): the admin-anchored title should land near the
                // hit, so a far jump / miss means HERE mis-resolved. Keep the
                // hit coordinate; clean the label via reverse geocode.
                return ResolvedPlace(
                    coordinate: hitCoord,
                    label: await cleanLabel(for: hit, at: hitCoord),
                    item: hit
                )
            }

            // 1a) NO admin (bare POI / port). Forward-geocoding the bare title
            //     is unreliable — TRUST the hit coordinate. Clean the label by
            //     reverse-geocoding to a "City, ST" the user can read.
            return ResolvedPlace(
                coordinate: hitCoord,
                label: await cleanLabel(for: hit, at: hitCoord),
                item: hit
            )
        }

        // ── Case 2: coordless / categorical hit — must forward-geocode. ─────
        let confirmed = (try? await geocode(query: hit.title, near: nil, limit: 5)) ?? []
        if let chosen = pickBestMatch(for: hit, among: confirmed), let cpos = chosen.position {
            return ResolvedPlace(
                coordinate: CLLocationCoordinate2D(latitude: cpos.lat, longitude: cpos.lng),
                label: chosen.displayLabel,
                item: chosen
            )
        }
        // No admin match and no single dominant result — return nil so the
        // caller keeps the typed text rather than inventing a wrong coord.
        return nil
    }

    /// Build a clean, user-facing "POI — City, ST" / "City, ST" label for a
    /// hit we've decided to trust by its own coordinate. Reverse-geocodes the
    /// coordinate to recover real admin (the bare-POI hit has none) and joins
    /// it with the POI name from the hit's title — never echoing HERE's
    /// malformed raw title ("Part near (of) …") on its own.
    private func cleanLabel(for hit: HereGeocodeItem,
                            at coord: CLLocationCoordinate2D) async -> String {
        // The POI name = the title's first segment, with HERE's "Part near
        // (of) …" prefix stripped. Empty if the title is purely admin.
        let poiName = Self.poiName(from: hit.title)

        // Recover City, ST from the coordinate itself.
        var cityST: String? = nil
        if let rev = try? await reverseGeocode(at: coord, limit: 1).first {
            let city = rev.address.city
            let region = rev.address.stateCode ?? rev.address.state
            switch (city, region) {
            case let (c?, r?): cityST = "\(c), \(r)"
            case let (c?, nil): cityST = c
            case let (nil, r?): cityST = r
            default: cityST = nil
            }
        }

        switch (poiName, cityST) {
        case let (poi?, cs?) where !poi.isEmpty:
            // Avoid "Houston, Houston, TX" when the POI already is the city.
            return poi.lowercased() == cs.split(separator: ",").first?
                .trimmingCharacters(in: .whitespaces).lowercased()
                ? cs : "\(poi) — \(cs)"
        case let (_, cs?):              return cs
        case let (poi?, nil) where !poi.isEmpty: return poi
        default:                        return hit.displayLabel
        }
    }

    /// The POI / place name portion of a HERE title: its first comma segment,
    /// with the malformed "Part near (of) " prefix HERE sometimes emits
    /// stripped off. Returns nil when nothing usable remains.
    static func poiName(from title: String) -> String? {
        var head = title.split(separator: ",").first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        for junk in ["Part near (of) ", "Part near of ", "Part near ", "Part of "] {
            if head.hasPrefix(junk) { head = String(head.dropFirst(junk.count)) }
        }
        head = head.trimmingCharacters(in: .whitespaces)
        return head.isEmpty ? nil : head
    }

    /// A coordinate is sane when it isn't the null-island (0,0) sentinel and
    /// is within valid lat/lng ranges.
    static func isSane(_ lat: Double, _ lng: Double) -> Bool {
        guard (-90...90).contains(lat), (-180...180).contains(lng) else { return false }
        return abs(lat) > 0.0001 || abs(lng) > 0.0001
    }

    /// Pick the geocode result that best corresponds to the picked hit.
    /// Pure — exposed for the selection policy above and unit-testable.
    ///
    /// REQUIRES an admin match OR a within-100-mi-of-hit result. There is NO
    /// unconditional `results.first` fallback: returning a same-named place on
    /// the wrong coast is worse than returning nil and keeping the hit coord.
    private func pickBestMatch(for hit: HereGeocodeItem,
                               among results: [HereGeocodeItem]) -> HereGeocodeItem? {
        guard !results.isEmpty else { return nil }

        func norm(_ s: String?) -> String? {
            s?.trimmingCharacters(in: .whitespaces).lowercased()
        }
        let hitCity  = norm(hit.address.city)
        let hitState = norm(hit.address.stateCode ?? hit.address.state)

        // 1) Admin match — same city + state as the picked hit. Only attempted
        //    when the hit actually carried admin (else this is skipped, NOT
        //    silently satisfied by a nil==nil match against an adminless hit).
        if hitCity != nil || hitState != nil {
            if let adminMatch = results.first(where: { r in
                let rCity  = norm(r.address.city)
                let rState = norm(r.address.stateCode ?? r.address.state)
                let cityOK  = hitCity  == nil || rCity  == hitCity
                let stateOK = hitState == nil || rState == hitState
                return cityOK && stateOK && r.position != nil
            }) {
                return adminMatch
            }
        }

        // 2) Nearest to the hit's own coordinate, if it had one and the
        //    nearest result is within a sane radius (defeats the phantom).
        if let hp = hit.position, Self.isSane(hp.lat, hp.lng) {
            let withPos = results.filter { $0.position != nil }
            if let nearest = withPos.min(by: {
                Self.greatCircleMiles(hp.lat, hp.lng, $0.position!.lat, $0.position!.lng)
                    < Self.greatCircleMiles(hp.lat, hp.lng, $1.position!.lat, $1.position!.lng)
            }) {
                let d = Self.greatCircleMiles(hp.lat, hp.lng,
                                              nearest.position!.lat, nearest.position!.lng)
                if d <= 100 { return nearest }
            }
        }

        // 3) For a coordless hit with no admin: accept ONLY a single dominant
        //    result (the geocoder was unambiguous). Multiple results with no
        //    way to disambiguate → nil, so the caller keeps the typed text.
        if hit.position == nil {
            let withPos = results.filter { $0.position != nil }
            if withPos.count == 1 { return withPos.first }
        }

        // No admin match, nothing within 100 mi of the hit, no unambiguous
        // dominant result → reject. NEVER blind `results.first`.
        return nil
    }

    /// Great-circle distance in statute miles. Used to detect an `at=`-biased
    /// phantom coordinate (a confirming result far from the picked hit).
    static func greatCircleMiles(_ aLat: Double, _ aLng: Double,
                                 _ bLat: Double, _ bLng: Double) -> Double {
        let r = 3959.0
        let dLat = (bLat - aLat) * .pi / 180
        let dLng = (bLng - aLng) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(aLat * .pi / 180) * cos(bLat * .pi / 180)
              * sin(dLng / 2) * sin(dLng / 2)
        return r * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    // MARK: - Helpers

    /// GET `url` with `Authorization: Bearer <token>`. On HTTP 401, invalidate
    /// the cached token and retry once before surfacing the error.
    ///
    /// RATE-LIMIT GATE: geocoding has its own 401 recipe (bypasses
    /// `HereBearerFetch`), so it pages through `HereRateLimiter.shared`
    /// directly for the same paced slot + deterministic 429 backoff.
    private func authorizedData(for url: URL) async throws -> Data {
        let lastRetryAfter = GeocodeRetryAfterBox()

        return try await HereRateLimiter.shared.runData(
            retryAfterFor: { _ in lastRetryAfter.seconds }
        ) { [session] in
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
                if http.statusCode == 429 {
                    lastRetryAfter.seconds = HereRateLimiter.retryAfterSeconds(from: http)
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                throw HereMapsError.http(http.statusCode, body)
            }
            return data
        }
    }
}

/// Carries a 429 `Retry-After` out of one gated geocode fetch into the
/// limiter's backoff hook. Confined to a single `runData` call.
private final class GeocodeRetryAfterBox: @unchecked Sendable {
    var seconds: TimeInterval?
}

// MARK: - Bridge to LoadLocation

extension HereGeocodeItem {
    /// Converts a HERE geocode hit to EusoTrip's `LoadLocation`.
    /// Returns `nil` for a coordless or null-island/out-of-range hit (e.g. a
    /// categorical result) — never fabricates a (0,0) coordinate. Callers must
    /// resolve such hits via `HereGeocodingClient.resolve(_:)` first.
    func asLoadLocation() -> LoadLocation? {
        guard let pos = position, HereGeocodingClient.isSane(pos.lat, pos.lng) else {
            return nil
        }
        return LoadLocation(
            address:  [address.houseNumber, address.street].compactMap { $0 }.joined(separator: " "),
            city:     address.city ?? "",
            state:    address.stateCode ?? address.state ?? "",
            zipCode:  address.postalCode ?? "",
            lat:      pos.lat,
            lng:      pos.lng
        )
    }
}
