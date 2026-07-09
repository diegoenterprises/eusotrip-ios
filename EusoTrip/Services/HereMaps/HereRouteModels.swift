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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
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

    struct TruckAttributes: Decodable {
        let weightLimitKg: Int?
        let heightLimitCm: Int?
        let widthLimitCm: Int?
        let lengthLimitCm: Int?
        let axleCountLimit: Int?
        let truckRestrictions: [String]?    // e.g. ["hazardousGoodsProhibited"]
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

    /// Clean, user-facing label derived from the STRUCTURED address rather
    /// than HERE's raw `title` — which can read "Barbour Ct, San Pedro, CA"
    /// for a Houston port query, or a malformed "Part near (of) …". We
    /// rebuild "<place/street>, City, ST" from the resolved admin fields so
    /// what the user sees always matches the coordinate we stored.
    var displayLabel: String {
        let city  = address.city
        let region = address.stateCode ?? address.state
        // Lead with the most specific named component HERE resolved.
        let lead: String? = {
            if let hn = address.houseNumber, let st = address.street {
                return "\(hn) \(st)"
            }
            if let st = address.street { return st }
            // For a place/locality the title's first segment is the POI /
            // locality name; keep it but strip any trailing admin echo so
            // we don't double up city/state below.
            let head = title.split(separator: ",").first.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            return head?.isEmpty == false ? head : address.district
        }()
        let parts = [lead, city, region]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        // De-dup if the lead already equals the city (e.g. "Dallas, Dallas").
        var seen = Set<String>()
        let deduped = parts.filter { seen.insert($0.lowercased()).inserted }
        return deduped.isEmpty ? title : deduped.joined(separator: ", ")
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
