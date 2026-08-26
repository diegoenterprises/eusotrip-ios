//
//  HereGeocodingClient.swift
//  EusoTrip — authenticated backend client for HERE Geocoding & Search v7
//
//  Provider credentials stay on the EusoTrip server. The app calls the typed
//  hereMaps.geocode / reverseGeocode / autosuggest procedures.
//
//  Docs: https://developer.here.com/documentation/geocoding-search-api/
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

actor HereGeocodingClient {

    static let shared = HereGeocodingClient()

    init(session: URLSession = .shared) {
        _ = session
    }

    // MARK: - Forward geocoding (address → lat/lng)

    /// Forward geocode an address string.
    /// - Parameter query: "1234 Main St, Dallas, TX"
    /// - Parameter near: Optional "prefer results near this lat/lng" hint.
    /// - Parameter limit: 1–20. HERE default is 20.
    func geocode(query: String,
                 near: CLLocationCoordinate2D? = nil,
                 limit: Int = 5) async throws -> [HereGeocodeItem] {
        let response: BackendGeocodeResponse = try await EusoTripAPI.shared.query(
            "hereMaps.geocode",
            input: BackendGeocodeInput(
                query: query,
                at: near.map(BackendCoord.init),
                country: nil,
                limit: min(20, max(1, limit))
            )
        )
        guard response.ok else { return [] }
        return response.items ?? []
    }

    // MARK: - Reverse geocoding (lat/lng → address)

    func reverseGeocode(at coordinate: CLLocationCoordinate2D,
                        limit: Int = 1) async throws -> [HereGeocodeItem] {
        _ = limit
        guard LatLongParser.isValid(coordinate) else { return [] }
        let response: BackendGeocodeResponse = try await EusoTripAPI.shared.query(
            "hereMaps.reverseGeocode",
            input: BackendCoord(coordinate)
        )
        guard response.ok else { return [] }
        return response.items ?? []
    }

    // MARK: - Autosuggest (address picker)

    /// For address-picker UI. HERE requires the `at=` hint to rank locally.
    func autosuggest(query: String,
                     near: CLLocationCoordinate2D,
                     limit: Int = 8) async throws -> [HereGeocodeItem] {
        let items: [HereGeocodeItem] = try await EusoTripAPI.shared.query(
            "hereMaps.autosuggest",
            input: BackendAutosuggestInput(
                query: query,
                anchor: BackendCoord(near),
                country: nil,
                limit: min(20, max(1, limit))
            )
        )
        return items
    }

    // MARK: - Confirming resolve (lock real coords to the chosen place)

    /// The outcome of confirming a picked suggestion: the true coordinate
    /// plus a clean label derived from the resolved structured address.
    struct ResolvedPlace {
        let coordinate: CLLocationCoordinate2D
        let formattedAddress: HereFormattedAddress
        var label: String { formattedAddress.label }
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
        if let pos = hit.position,
           let hitCoord = LatLongParser.validatedCoordinate(
               latitude: pos.lat,
               longitude: pos.lng
           ) {

            if hit.hasExplicitAdmin {
                // 1b) HAS admin — anchor the forward geocode on the admin-
                //     bearing title, require an admin match, and gate it to
                //     within 100 mi of the hit's own coordinate.
                let confirmed = (try? await geocode(query: hit.title, near: nil, limit: 5)) ?? []
                if let chosen = pickBestMatch(for: hit, among: confirmed),
                   let cpos = chosen.position,
                   let confirmedCoordinate = LatLongParser.validatedCoordinate(
                       latitude: cpos.lat,
                       longitude: cpos.lng
                   ),
                   Self.greatCircleMiles(pos.lat, pos.lng, cpos.lat, cpos.lng) <= 100 {
                    return ResolvedPlace(
                        coordinate: confirmedCoordinate,
                        formattedAddress: chosen.formattedAddress(provenance: .hereGeocode),
                        item: chosen
                    )
                }
                // Forward geocode produced no admin match within 100 mi (or
                // none at all): the admin-anchored title should land near the
                // hit, so a far jump / miss means HERE mis-resolved. Keep the
                // hit coordinate; clean the label via reverse geocode.
                return ResolvedPlace(
                    coordinate: hitCoord,
                    formattedAddress: await cleanAddress(for: hit, at: hitCoord),
                    item: hit
                )
            }

            // 1a) NO admin (bare POI / port). Forward-geocoding the bare title
            //     is unreliable — TRUST the hit coordinate. Clean the label by
            //     reverse-geocoding to a "City, ST" the user can read.
            return ResolvedPlace(
                coordinate: hitCoord,
                formattedAddress: await cleanAddress(for: hit, at: hitCoord),
                item: hit
            )
        }

        // ── Case 2: coordless / categorical hit — must forward-geocode. ─────
        let confirmed = (try? await geocode(query: hit.title, near: nil, limit: 5)) ?? []
        if let chosen = pickBestMatch(for: hit, among: confirmed),
           let cpos = chosen.position,
           let coordinate = LatLongParser.validatedCoordinate(
               latitude: cpos.lat,
               longitude: cpos.lng
           ) {
            return ResolvedPlace(
                coordinate: coordinate,
                formattedAddress: chosen.formattedAddress(provenance: .hereGeocode),
                item: chosen
            )
        }
        // No admin match and no single dominant result — return nil so the
        // caller keeps the typed text rather than inventing a wrong coord.
        return nil
    }

    /// Reverse-geocode a trusted suggestion coordinate and retain the exact
    /// HERE source that authored the resulting street/admin components.
    private func cleanAddress(
        for hit: HereGeocodeItem,
        at coord: CLLocationCoordinate2D
    ) async -> HereFormattedAddress {
        // The POI name = the title's first segment, with HERE's "Part near
        // (of) …" prefix stripped. Empty if the title is purely admin.
        let poiName = Self.poiName(from: hit.title)

        if let rev = try? await reverseGeocode(at: coord, limit: 1).first {
            return rev.formattedAddress(
                provenance: .hereReverseGeocode,
                place: poiName
            )
        }
        return hit.formattedAddress(
            provenance: .hereAutosuggest,
            place: poiName
        )
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

    /// A coordinate is sane when both axes are finite and within WGS-84.
    static func isSane(_ lat: Double, _ lng: Double) -> Bool {
        LatLongParser.validatedCoordinate(latitude: lat, longitude: lng) != nil
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

    private struct BackendCoord: Encodable {
        let lat: Double
        let lng: Double

        init(_ coordinate: CLLocationCoordinate2D) {
            lat = coordinate.latitude
            lng = coordinate.longitude
        }
    }

    private struct BackendGeocodeInput: Encodable {
        let query: String
        let at: BackendCoord?
        let country: String?
        let limit: Int?
    }

    private struct BackendAutosuggestInput: Encodable {
        let query: String
        let anchor: BackendCoord
        let country: String?
        let limit: Int?
    }

    private struct BackendGeocodeResponse: Decodable {
        let ok: Bool
        let items: [HereGeocodeItem]?
    }
}

// MARK: - Bridge to LoadLocation

extension HereGeocodeItem {
    /// Converts a HERE geocode hit to EusoTrip's `LoadLocation`.
    /// Returns `nil` for a coordless or out-of-range hit (e.g. a categorical
    /// result). Missing axes remain missing; `(0,0)` remains valid. Callers must
    /// resolve such hits via `HereGeocodingClient.resolve(_:)` first.
    func asLoadLocation() -> LoadLocation? {
        guard let pos = position, HereGeocodingClient.isSane(pos.lat, pos.lng) else {
            return nil
        }
        let formatted = formattedAddress(provenance: .hereGeocode)
        return LoadLocation(
            address:  formatted.street ?? formatted.place ?? "Unknown",
            city:     formatted.city ?? "Unknown",
            state:    formatted.state ?? "Unknown",
            zipCode:  address.postalCode ?? "",
            lat:      pos.lat,
            lng:      pos.lng
        )
    }
}
