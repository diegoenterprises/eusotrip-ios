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
    let id: String
    let sections: [HereRouteSection]
}

/// One section of a route (typically = one leg between two waypoints).
struct HereRouteSection: Decodable, Identifiable {
    let id: String
    let type: String            // "vehicle", "ferry", "pedestrian"
    let departure: HereSectionEndpoint
    let arrival:   HereSectionEndpoint
    let summary:   HereSectionSummary?
    let polyline:  String       // flexible polyline, needs decoding
    let notices:   [HereNotice]?
    let spans:     [HereSpan]?
    let tolls:     [HereToll]?
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
/// only populated when the request asked for `return=polyline,summary,spans`.
struct HereSpan: Decodable {
    let offset: Int
    let length: Int?
    let names: [NamedValue]?
    let routeNumbers: [NamedValue]?
    let speedLimit: Double?
    let countryCode: String?
    let stateCode:   String?
    let functionalClass: Int?
    let truckAttributes: TruckAttributes?

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
    let position: HerePlace.Coord
    let mapView: MapView?

    struct MapView: Decodable {
        let west:  Double
        let south: Double
        let east:  Double
        let north: Double
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
