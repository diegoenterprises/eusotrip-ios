//
//  HereTrafficClient.swift
//  EusoTrip — authenticated backend client for HERE Real-Time Traffic v7.
//
//  Covers both surfaces of the Traffic API:
//
//    GET https://data.traffic.hereapi.com/v7/flow        — jam factor,
//                                                          current
//                                                          speed,
//                                                          free-flow
//                                                          baseline
//    GET https://data.traffic.hereapi.com/v7/incidents   — incidents,
//                                                          roadworks,
//                                                          closures
//                                                          (powers
//                                                          "HERE Road
//                                                          Alerts" in
//                                                          the Dynamic
//                                                          Map Content
//                                                          catalogue)
//
//  Common geo filter:
//      in=bbox:west,south,east,north
//      in=circle:lat,lng;r=<meters>
//      in=corridor:<flexible-polyline>;w=<meters>   (route corridor)
//
//  Common optional:
//      locationReferencing=shape          (ship the actual polyline)
//      criticality=minor,major,critical   (incidents)
//      type=accident,roadworks,…          (incidents)
//
//  Provider credentials stay on the EusoTrip server.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

// MARK: - Flow (Real-Time Traffic)

struct HereTrafficFlowResponse: Decodable {
    let sourceUpdated: String?
    let results: [HereTrafficFlowResult]
}

struct HereTrafficFlowResult: Decodable, Identifiable, Hashable {
    /// Synthetic identity — server doesn't ship one per result row,
    /// so we derive from the coordinate span + sampling time.
    var id: String {
        if let point = location?.shape?.links?.first?.points?.first,
           let coordinate = LatLongParser.validatedCoordinate(
               latitude: point.lat,
               longitude: point.lng
           ) {
            return "\(LatLongParser.displayString(coordinate))-\(sourceUpdated ?? "unknown-time")"
        }
        return "unlocated-\(location?.description ?? "unknown-segment")-\(sourceUpdated ?? "unknown-time")"
    }
    let location: HereTrafficLocation?
    let currentFlow: HereTrafficFlow?
    let sourceUpdated: String?
}

struct HereTrafficLocation: Decodable, Hashable {
    let shape: HereTrafficShape?
    let length: Double?
    let description: String?
}

struct HereTrafficShape: Decodable, Hashable {
    let links: [HereTrafficLink]?
}

struct HereTrafficLink: Decodable, Hashable {
    let points: [HerePoint]?
    let length: Double?
    let functionalClass: Int?
}

struct HerePoint: Decodable, Hashable {
    let lat: Double
    let lng: Double
    var coordinate: CLLocationCoordinate2D? {
        LatLongParser.validatedCoordinate(latitude: lat, longitude: lng)
    }
}

/// Snapshot of the traffic state on a link. `jamFactor` scales
/// 0 (free flow) → 10 (closed); 4-7 is slow, 7-9 is queued, 9-10 is
/// stopped. `speed` is the live sample, `freeFlow` is the baseline.
struct HereTrafficFlow: Decodable, Hashable {
    let speed: Double?
    let speedUncapped: Double?
    let freeFlow: Double?
    let jamFactor: Double?
    let confidence: Double?
    let traversability: String?
    /// Segments that are closed have jamFactor = 10 and a
    /// "subSegment" with `type == "closed"`.
    let subSegments: [HereTrafficSubSegment]?
}

struct HereTrafficSubSegment: Decodable, Hashable {
    let start: Double?
    let length: Double?
    let jamFactor: Double?
    let speed: Double?
    let freeFlow: Double?
    let type: String?
}

// MARK: - Incidents (Road Alerts)

struct HereIncidentsResponse: Decodable {
    let sourceUpdated: String?
    let results: [HereIncident]
}

struct HereIncident: Decodable, Identifiable, Hashable {
    let incidentDetails: HereIncidentDetails?
    let location: HereTrafficLocation?
    let sourceUpdated: String?

    var id: String { incidentDetails?.id ?? (incidentDetails?.description ?? "") + (sourceUpdated ?? "") }
}

struct HereIncidentDetails: Decodable, Hashable {
    let id: String?
    /// "accident" | "roadworks" | "closure" | "hazard" | "weather" |
    /// "massTransit" | "disaster" | "other"
    let type: String?
    /// "minor" | "major" | "critical"
    let criticality: String?
    let roadClosed: Bool?
    let description: String?
    let summary: String?
    let startTime: String?
    let endTime: String?
    let verified: Bool?
}

// MARK: - Client

final class HereTrafficClient {
    static let shared = HereTrafficClient()

    init(session: URLSession = .shared) {
        _ = session
    }

    /// Flow around a point. Radius in meters. Use for en-route
    /// "how bad is traffic up ahead" chips and the heatmap layer
    /// behind the current load leg.
    func flow(
        near center: CLLocationCoordinate2D,
        radiusMeters: Int = 15_000,
        includeShape: Bool = true
    ) async throws -> [HereTrafficFlowResult] {
        guard LatLongParser.isValid(center) else { return [] }
        let rows: [BackendFlow] = try await EusoTripAPI.shared.query(
            "hereMaps.trafficFlow",
            input: BackendFlowRequest(
                bbox: Self.bbox(center: center, radiusMeters: radiusMeters),
                minJamFactor: 0
            )
        )
        return rows.map { row in
            let rawPath: [BackendPoint] = includeShape ? row.path : []
            let points: [HerePoint] = rawPath.compactMap { point in
                guard let coordinate = LatLongParser.validatedCoordinate(
                    latitude: point.lat,
                    longitude: point.lng
                ) else { return nil }
                return HerePoint(lat: coordinate.latitude, lng: coordinate.longitude)
            }
            let location = HereTrafficLocation(
                shape: HereTrafficShape(
                    links: points.isEmpty
                        ? nil
                        : [HereTrafficLink(points: points, length: nil, functionalClass: nil)]
                ),
                length: nil,
                description: row.description
            )
            return HereTrafficFlowResult(
                location: location,
                currentFlow: HereTrafficFlow(
                    speed: row.speedKph,
                    speedUncapped: nil,
                    freeFlow: row.freeFlowKph,
                    jamFactor: row.jamFactor,
                    confidence: row.confidence,
                    traversability: row.jamFactor >= 10 ? "closed" : "open",
                    subSegments: nil
                ),
                sourceUpdated: nil
            )
        }
    }

    /// Incidents around a point. Defaults to major+critical severity
    /// so the en-route chip strip isn't dominated by low-priority
    /// advisories. Pass `criticality: []` for every incident.
    func incidents(
        near center: CLLocationCoordinate2D,
        radiusMeters: Int = 30_000,
        criticality: [String] = ["major", "critical"]
    ) async throws -> [HereIncident] {
        guard LatLongParser.isValid(center) else { return [] }
        let minimum: Int = criticality.isEmpty
            ? 0
            : (criticality.contains("major") ? 2 : (criticality.contains("critical") ? 3 : 1))
        let rows: [BackendIncident] = try await EusoTripAPI.shared.query(
            "hereMaps.trafficIncidents",
            input: BackendIncidentRequest(
                bbox: Self.bbox(center: center, radiusMeters: radiusMeters),
                criticalityMin: minimum
            )
        )
        return rows.compactMap { row in
            guard let coordinate = LatLongParser.validatedCoordinate(
                latitude: row.lat,
                longitude: row.lng
            ) else { return nil }
            return HereIncident(
                incidentDetails: HereIncidentDetails(
                    id: row.id,
                    type: row.type,
                    criticality: row.severity,
                    roadClosed: row.severity == "critical",
                    description: row.description,
                    summary: row.road,
                    startTime: row.startTime,
                    endTime: row.endTime,
                    verified: nil
                ),
                location: HereTrafficLocation(
                    shape: HereTrafficShape(
                        links: [
                            HereTrafficLink(
                                points: [HerePoint(
                                    lat: coordinate.latitude,
                                    lng: coordinate.longitude
                                )],
                                length: nil,
                                functionalClass: nil
                            )
                        ]
                    ),
                    length: nil,
                    description: row.road
                ),
                sourceUpdated: nil
            )
        }
    }

    private static func bbox(
        center: CLLocationCoordinate2D,
        radiusMeters: Int
    ) -> BackendBBox {
        let radius = Double(max(100, radiusMeters))
        let latDelta = radius / 111_320
        let cosine = max(0.01, abs(cos(center.latitude * .pi / 180)))
        let lngDelta = radius / (111_320 * cosine)
        return BackendBBox(
            north: min(90, center.latitude + latDelta),
            south: max(-90, center.latitude - latDelta),
            east: min(180, center.longitude + lngDelta),
            west: max(-180, center.longitude - lngDelta)
        )
    }

    private struct BackendBBox: Codable {
        let north: Double
        let south: Double
        let east: Double
        let west: Double
    }

    private struct BackendFlowRequest: Encodable {
        let bbox: BackendBBox
        let minJamFactor: Double
    }

    private struct BackendFlow: Decodable {
        let lat: Double
        let lng: Double
        let path: [BackendPoint]
        let jamFactor: Double
        let speedKph: Double
        let freeFlowKph: Double
        let confidence: Double
        let description: String?
    }

    private struct BackendPoint: Codable {
        let lat: Double
        let lng: Double
    }

    private struct BackendIncidentRequest: Encodable {
        let bbox: BackendBBox
        let criticalityMin: Int
    }

    private struct BackendIncident: Decodable {
        let id: String
        let type: String
        let severity: String
        let startTime: String
        let endTime: String?
        let description: String
        let lat: Double
        let lng: Double
        let road: String?
    }
}
