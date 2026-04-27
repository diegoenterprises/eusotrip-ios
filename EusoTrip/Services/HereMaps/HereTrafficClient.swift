//
//  HereTrafficClient.swift
//  EusoTrip — REST client for HERE Real-Time Traffic v7.
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
//  Auth: Bearer via HereBearerFetch.
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
        let lat = location?.shape?.links?.first?.points?.first?.lat ?? 0
        let lng = location?.shape?.links?.first?.points?.first?.lng ?? 0
        return "\(lat)-\(lng)-\(sourceUpdated ?? "")"
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
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
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

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Flow around a point. Radius in meters. Use for en-route
    /// "how bad is traffic up ahead" chips and the heatmap layer
    /// behind the current load leg.
    func flow(
        near center: CLLocationCoordinate2D,
        radiusMeters: Int = 15_000,
        includeShape: Bool = true
    ) async throws -> [HereTrafficFlowResult] {
        var comps = URLComponents(string: "https://data.traffic.hereapi.com/v7/flow")!
        var items: [URLQueryItem] = [
            URLQueryItem(
                name: "in",
                value: "circle:\(center.latitude),\(center.longitude);r=\(radiusMeters)"
            )
        ]
        if includeShape {
            items.append(URLQueryItem(name: "locationReferencing", value: "shape"))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw HereMapsError.badURL }

        let data = try await HereBearerFetch.data(for: url, session: session)
        do {
            return try decoder.decode(HereTrafficFlowResponse.self, from: data).results
        } catch {
            throw HereMapsError.decoding(String(describing: error))
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
        var comps = URLComponents(string: "https://data.traffic.hereapi.com/v7/incidents")!
        var items: [URLQueryItem] = [
            URLQueryItem(
                name: "in",
                value: "circle:\(center.latitude),\(center.longitude);r=\(radiusMeters)"
            ),
            URLQueryItem(name: "locationReferencing", value: "shape"),
        ]
        if !criticality.isEmpty {
            items.append(URLQueryItem(name: "criticality", value: criticality.joined(separator: ",")))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw HereMapsError.badURL }

        let data = try await HereBearerFetch.data(for: url, session: session)
        do {
            return try decoder.decode(HereIncidentsResponse.self, from: data).results
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }
}
