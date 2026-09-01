//
//  HereRouteModels.swift
//  EusoTrip — Codable mirrors of HERE Routing API v8 response shapes
//
//  Only the fields EusoTrip actually consumes are modelled. HERE returns a
//  very wide response; adding fields here is safe because Swift's JSONDecoder
//  ignores unknown keys by default.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

// MARK: - Top-level response

/// Envelope returned by `GET /v8/routes`.
struct HereRoutesResponse: Decodable {
    let routes: [HereRoute]
}

/// A single computed route.
struct HereRoute: Decodable, Identifiable {
    // 2026-06-03 — HERE Routing v8 does NOT return `id` on route/section
    // unless routeHandle/labels are requested (this client requests only
    // polyline/summary/actions). A non-optional `id` made JSONDecoder throw
    // keyNotFound on EVERY 200-OK response, discarding the route before its
    // polyline was ever read — the root cause of "no map works anywhere".
    let id: String?
    let sections: [HereRouteSection]
}

/// One section of a route (typically = one leg between two waypoints).
struct HereRouteSection: Decodable, Identifiable {
    let id: String?
    let type: String            // "vehicle", "ferry", "pedestrian"
    let departure: HereSectionEndpoint
    let arrival:   HereSectionEndpoint
    let summary:   HereSectionSummary?
    let polyline:  String       // flexible polyline, needs decoding
    let notices:   [HereNotice]?
    let spans:     [HereSpan]?
    let tolls:     [HereToll]?
    /// Turn-by-turn maneuvers. Present because the routing request already asks
    /// for `return=polyline,summary,actions,tolls`. Each `offset` indexes into
    /// this section's DECODED polyline coords (via `HereFlexiblePolyline.decode`).
    let actions:   [HereRouteAction]?

    // Declared explicitly: Swift only synthesises CodingKeys when it also
    // synthesises the conformance, and this type supplies its own init(from:).
    private enum CodingKeys: String, CodingKey {
        case id, type, departure, arrival, summary, polyline
        case notices, spans, tolls, actions
    }

    /// Split deliberately into ESSENTIAL and ANNOTATION fields.
    ///
    /// A HERE response decodes as one value, so before this a shape change in
    /// any optional annotation threw away the whole route — twice now, and both
    /// times the symptom was "nothing works" rather than "one field is wrong"
    /// (2026-06-03 non-optional `id`; 2026-08-07 `truckAttributes` array).
    ///
    /// Essentials stay STRICT: without a polyline or endpoints there is no
    /// route, and pretending otherwise would be the dishonest kind of fallback.
    /// Annotations (summary, spans, tolls, actions, notices) degrade to nil, so
    /// upstream drift costs a speed-limit overlay instead of navigation. The
    /// drift itself is caught by the contract test, not hidden by this.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type      = try c.decode(String.self, forKey: .type)
        departure = try c.decode(HereSectionEndpoint.self, forKey: .departure)
        arrival   = try c.decode(HereSectionEndpoint.self, forKey: .arrival)
        polyline  = try c.decode(String.self, forKey: .polyline)
        id        = try? c.decodeIfPresent(String.self, forKey: .id)
        summary   = try? c.decodeIfPresent(HereSectionSummary.self, forKey: .summary)
        notices   = try? c.decodeIfPresent([HereNotice].self, forKey: .notices)
        spans     = try? c.decodeIfPresent([HereSpan].self, forKey: .spans)
        tolls     = try? c.decodeIfPresent([HereToll].self, forKey: .tolls)
        actions   = try? c.decodeIfPresent([HereRouteAction].self, forKey: .actions)
    }
}

/// A single HERE-authored driving maneuver (L13-3 turn-by-turn).
struct HereRouteAction: Decodable, Equatable {
    let action: String              // "depart" | "turn" | "continue" | "exit" | "arrive" …
    let duration: Int?              // seconds
    let length: Int?                // meters
    let offset: Int?                // index into the section's DECODED polyline coords
    let instruction: String?        // HERE-authored, e.g. "Take exit 228 toward Macon."
    let direction: String?          // "left" | "right" | "slightLeft" …
    let severity: String?
}

struct HereSectionEndpoint: Decodable {
    let time: String            // ISO-8601
    let place: HerePlace
}

struct HerePlace: Decodable {
    struct Coord: Decodable { let lat: Double; let lng: Double }
    let location: Coord
    let originalLocation: Coord?
    let type: String?           // "place", "waypoint", etc.

    var coordinate: CLLocationCoordinate2D? {
        LatLongParser.validatedCoordinate(
            latitude: location.lat,
            longitude: location.lng
        )
    }
}

/// Leg totals.
struct HereSectionSummary: Decodable {
    let duration: Int           // seconds
    let length:   Int           // meters
    let baseDuration: Int?      // seconds w/o traffic
    let typicalDuration: Int?   // seconds in typical traffic
}

/// Any warning the router raised — speed limits, time-of-day restrictions,
/// truck restrictions violated but unavoidable, etc.
struct HereNotice: Decodable {
    let title: String
    let code:  String?
    let severity: String?       // "info" | "critical"
}

/// Per-span metadata (speed limits, road class, country codes). Optional —
/// only populated when the request asked for `return=polyline,...` and the
/// separate `spans=` query param.
struct HereSpan: Decodable {
    let offset: Int
    let length: Int?
    let names: [NamedValue]?
    let routeNumbers: [NamedValue]?
    /// HERE v8's current span speed field. Older responses and a few local
    /// callsites still know the deprecated `speedLimit`, so decode both.
    let maxSpeed: Double?
    let speedLimit: Double?
    let countryCode: String?
    let stateCode:   String?
    let functionalClass: Int?
    let truckAttributes: TruckAttributes?

    var effectiveMaxSpeed: Double? { maxSpeed ?? speedLimit }

    struct NamedValue: Decodable {
        let value: String
        let language: String?
    }

    /// HERE Routing v8 returns `truckAttributes` as an **ARRAY OF STRING FLAGS**
    /// — live-verified 2026-08-07 against router.hereapi.com/v8:
    ///
    ///     "spans": [ { "offset": 0, "truckAttributes": ["open"], … } ]
    ///
    /// It was modelled here as a keyed object, so `JSONDecoder` threw
    /// `typeMismatch` ("expected Dictionary, found array") on the first span
    /// carrying the field. A response decodes as ONE value, so that single
    /// mismatch discarded the entire route — and because the server sends
    /// `spans=maxSpeed,functionalClass,truckAttributes,notices` whenever it
    /// asks for a polyline (the default path), EVERY route calculation failed.
    /// Same class as the 2026-06-03 non-optional `id` bug that took out every
    /// map: one wrong field type in optional metadata, whole feature dead.
    ///
    /// Both shapes decode, so neither a rollback nor a future HERE change to
    /// the object form can break routing again.
    struct TruckAttributes: Decodable {
        /// The flags HERE actually sends today, e.g. ["open"], ["tunnelCategoryB"].
        let flags: [String]

        // Legacy/object form. HERE does not currently send these; they decode
        // if it ever does, and are nil otherwise.
        let weightLimitKg: Int?
        let heightLimitCm: Int?
        let widthLimitCm: Int?
        let lengthLimitCm: Int?
        let axleCountLimit: Int?
        let truckRestrictions: [String]?    // e.g. ["hazardousGoodsProhibited"]

        private enum CodingKeys: String, CodingKey {
            case weightLimitKg, heightLimitCm, widthLimitCm, lengthLimitCm
            case axleCountLimit, truckRestrictions
        }

        init(from decoder: Decoder) throws {
            // Array form first — this is what HERE v8 actually returns.
            if let unkeyed = try? decoder.singleValueContainer(),
               let values = try? unkeyed.decode([String].self) {
                flags = values
                weightLimitKg = nil; heightLimitCm = nil; widthLimitCm = nil
                lengthLimitCm = nil; axleCountLimit = nil; truckRestrictions = nil
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            flags = []
            weightLimitKg   = try c.decodeIfPresent(Int.self, forKey: .weightLimitKg)
            heightLimitCm   = try c.decodeIfPresent(Int.self, forKey: .heightLimitCm)
            widthLimitCm    = try c.decodeIfPresent(Int.self, forKey: .widthLimitCm)
            lengthLimitCm   = try c.decodeIfPresent(Int.self, forKey: .lengthLimitCm)
            axleCountLimit  = try c.decodeIfPresent(Int.self, forKey: .axleCountLimit)
            truckRestrictions = try c.decodeIfPresent([String].self, forKey: .truckRestrictions)
        }
    }
}

/// A toll event (for settlements / IFTA cost breakdowns).
struct HereToll: Decodable {
    let countryCode: String?
    let tollSystem: String?
    let fares: [Fare]?

    struct Fare: Decodable {
        let id: String?
        let name: String?
        let price: Price?
        struct Price: Decodable {
            let value: Double
            let currency: String
        }
    }
}

// MARK: - Geocoding v7 response

struct HereGeocodeResponse: Decodable {
    let items: [HereGeocodeItem]
}

struct HereGeocodeItem: Decodable, Identifiable {
    let id: String
    let title: String
    let address: HereAddress
    // Autosuggest can return category/chain hits with NO position. Geocode
    // hits always carry one. Optional so a coordless autosuggest item still
    // decodes (it's resolved with a confirming geocode of its title).
    let position: HerePlace.Coord?
    let mapView: MapView?
    // HERE result class — "place", "locality", "administrativeArea",
    // "street", "houseNumber", "addressBlock", "intersection",
    // "postalCodePoint", "chainQuery", "categoryQuery". Drives the
    // confirming-resolve decision: a `*Query` / coordless hit must be
    // forward-geocoded; a discrete hit can be admin-verified.
    let resultType: String?

    struct MapView: Decodable {
        let west:  Double
        let south: Double
        let east:  Double
        let north: Double
    }

    /// True when this hit is a category/chain query placeholder, not a
    /// discrete resolved location (no usable coordinate of its own).
    var isCategorical: Bool {
        position == nil
            || resultType == "chainQuery"
            || resultType == "categoryQuery"
    }

    /// True when the hit carries explicit administrative context — either
    /// structured city+state from HERE's address block, OR a title that ends
    /// in ", City, ST" (a 2-letter US state abbreviation). Drives the
    /// admin-aware resolve policy: an admin-bearing hit is forward-geocoded
    /// (admin-anchored, sanity-gated); a bare POI / port without admin is
    /// trusted by its own ride-along coordinate.
    var hasExplicitAdmin: Bool {
        let hasStructured = (address.city?.isEmpty == false)
            && ((address.stateCode ?? address.state)?.isEmpty == false)
        if hasStructured { return true }

        // Title-borne admin: "Terminal Island, Los Angeles, CA" — last segment
        // is a 2-letter state code and there are ≥3 comma segments (POI, city,
        // state). A bare "Port of Houston-Barbours Cut Terminal" has none.
        let segs = title.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard segs.count >= 3, let last = segs.last else { return false }
        let isStateCode = last.count == 2
            && last.uppercased() == last
            && last.allSatisfy { $0.isLetter }
        return isStateCode
    }

    func formattedAddress(
        provenance: HereAddressProvenance,
        place: String? = nil
    ) -> HereFormattedAddress {
        HereAddressFormatter.format(
            address: address,
            place: place,
            fallbackTitle: title,
            provenance: provenance
        )
    }

    /// Compatibility label for existing call sites. New address flows should
    /// retain the full `HereFormattedAddress` so provider provenance is not
    /// discarded at the UI boundary.
    var displayLabel: String {
        formattedAddress(provenance: .hereGeocode).label
    }
}

struct HereAddress: Decodable {
    let label: String?
    let countryCode: String?
    let countryName: String?
    let stateCode: String?
    let state: String?
    let county: String?
    let city: String?
    let district: String?
    let street: String?
    let postalCode: String?
    let houseNumber: String?
}

enum HereAddressProvenance: String, Codable, Equatable, Sendable {
    case userEntered
    case coordinateInput
    case hereAutosuggest
    case hereGeocode
    case hereReverseGeocode

    var provider: String? {
        switch self {
        case .hereAutosuggest, .hereGeocode, .hereReverseGeocode:
            return "HERE"
        case .userEntered, .coordinateInput:
            return nil
        }
    }
}

struct HereFormattedAddress: Equatable, Sendable {
    let place: String?
    let street: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let label: String
    let provenance: HereAddressProvenance

    var provider: String? { provenance.provider }
    var isKnown: Bool { label != HereAddressFormatter.unknownLabel }
}

enum HereAddressFormatter {
    static let unknownLabel = "Unknown address"

    static func format(
        address: HereAddress,
        place explicitPlace: String? = nil,
        fallbackTitle: String? = nil,
        provenance: HereAddressProvenance
    ) -> HereFormattedAddress {
        let streetName = clean(address.street)
        let houseNumber = clean(address.houseNumber)
        let street = [houseNumber, streetName]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
        let city = clean(address.city)
        let state = clean(address.stateCode) ?? clean(address.state)
        let postalCode = clean(address.postalCode)
        let country = clean(address.countryName) ?? clean(address.countryCode)

        let titlePlace = cleanPlace(fallbackTitle?.split(separator: ",").first.map(String.init))
        let place = cleanPlace(explicitPlace)
            ?? (street == nil ? titlePlace : nil)
            ?? clean(address.district)

        let region = [state, postalCode]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
        let components = deduplicated([place, street, city, region, country])
        let label = components.isEmpty ? unknownLabel : components.joined(separator: ", ")

        return HereFormattedAddress(
            place: place,
            street: street,
            city: city,
            state: state,
            postalCode: postalCode,
            country: country,
            label: label,
            provenance: provenance
        )
    }

    private static func clean(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .nilIfEmpty
    }

    private static func cleanPlace(_ value: String?) -> String? {
        guard var place = clean(value) else { return nil }
        for prefix in ["Part near (of) ", "Part near of ", "Part near ", "Part of "] {
            if let range = place.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                place.removeSubrange(range)
                break
            }
        }
        return clean(place)
    }

    private static func deduplicated(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let value = clean(value) else { return nil }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? value : nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Matrix v8 response

struct HereMatrixResponse: Decodable {
    let matrix: Matrix
    let regionDefinition: Region?

    struct Matrix: Decodable {
        let numOrigins: Int
        let numDestinations: Int
        /// Flat row-major array: row-major `numDestinations` per row.
        let travelTimes: [Int]?
        let distances:   [Int]?
    }

    struct Region: Decodable {
        let type: String
    }
}

// MARK: - Isoline v8 response

struct HereIsolineResponse: Decodable {
    let isolines: [Isoline]

    struct Isoline: Decodable {
        let range: Range
        let polygons: [Polygon]

        struct Range: Decodable {
            let type: String          // "time" | "distance"
            let value: Int            // seconds or meters
        }
        struct Polygon: Decodable {
            let outer: String         // flexible polyline
            let inner: [String]?
        }
    }
}
