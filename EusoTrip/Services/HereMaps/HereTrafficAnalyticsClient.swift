//
//  HereTrafficAnalyticsClient.swift
//  EusoTrip — HERE current and recent traffic speed profiles.
//
//  Current readings come from HERE Traffic API v7 flow. Recent historical
//  route readings come from HERE Map Attributes API v8 traffic speed records.
//  The archive contract is path-scoped; the backend intentionally returns no
//  rows for a historical bbox instead of substituting current or fake data.
//
//  Provider credentials stay on the EusoTrip server.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

struct HereTrafficSpeedSample: Decodable, Identifiable, Hashable {
    let linkId: String
    let lat: Double
    let lng: Double
    /// UTC weekday using HERE's server contract: Monday = 0, Sunday = 6.
    let dayOfWeek: Int
    /// UTC hour, 0...23.
    let hourOfDay: Int
    let meanMph: Double
    let freeFlowMph: Double?
    let congestionIndex: Double
    /// HERE supplies confidence rather than a probe count.
    let sampleCount: Int?
    let source: String
    let observedAt: String
    let confidence: Double?
    let jamFactor: Double?
    let traversability: String?

    var id: String { "\(source):\(linkId):\(observedAt)" }

    var coordinate: CLLocationCoordinate2D? {
        LatLongParser.validatedCoordinate(latitude: lat, longitude: lng)
    }
}

struct HereTrafficAnalyticsBounds: Encodable, Hashable {
    let minLat: Double
    let minLng: Double
    let maxLat: Double
    let maxLng: Double

    var isValid: Bool {
        [minLat, minLng, maxLat, maxLng].allSatisfy(\.isFinite)
            && (-90...90).contains(minLat)
            && (-90...90).contains(maxLat)
            && (-180...180).contains(minLng)
            && (-180...180).contains(maxLng)
            && minLat < maxLat
            && minLng < maxLng
    }
}

final class HereTrafficAnalyticsClient {
    static let shared = HereTrafficAnalyticsClient()

    init(session: URLSession = .shared) {
        _ = session
    }

    /// Current Traffic v7 speed-vs-free-flow readings inside a bbox. A past
    /// day/hour returns an honest empty array because the archive is path-only.
    func speeds(
        in bounds: HereTrafficAnalyticsBounds,
        dayOfWeek: Int? = nil,
        hourOfDay: Int? = nil
    ) async throws -> [HereTrafficSpeedSample] {
        guard bounds.isValid,
              Self.valid(dayOfWeek: dayOfWeek, hourOfDay: hourOfDay) else {
            return []
        }
        return try await EusoTripAPI.shared.query(
            "hereMaps.historicalSpeedsInBbox",
            input: BboxRequest(
                minLat: bounds.minLat,
                minLng: bounds.minLng,
                maxLat: bounds.maxLat,
                maxLng: bounds.maxLng,
                dayOfWeek: dayOfWeek,
                hourOfDay: hourOfDay
            )
        )
    }

    /// With no temporal filter this uses live Traffic v7 flow. A recent
    /// departure or day/hour bucket selects Map Attributes v8's path archive.
    func speeds(
        along flexiblePolyline: String,
        dayOfWeek: Int? = nil,
        hourOfDay: Int? = nil,
        departureTime: Date? = nil,
        widthMeters: Int? = nil
    ) async throws -> [HereTrafficSpeedSample] {
        let polyline = flexiblePolyline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard polyline.count >= 4,
              Self.valid(dayOfWeek: dayOfWeek, hourOfDay: hourOfDay),
              widthMeters.map({ (5...200).contains($0) }) ?? true else {
            return []
        }
        return try await EusoTripAPI.shared.query(
            "hereMaps.historicalSpeedsAlongRoute",
            input: RouteRequest(
                polyline: polyline,
                dayOfWeek: dayOfWeek,
                hourOfDay: hourOfDay,
                departureTime: departureTime.map { ISO8601DateFormatter().string(from: $0) },
                widthMeters: widthMeters
            )
        )
    }

    private static func valid(dayOfWeek: Int?, hourOfDay: Int?) -> Bool {
        (dayOfWeek.map({ (0...6).contains($0) }) ?? true)
            && (hourOfDay.map({ (0...23).contains($0) }) ?? true)
    }

    private struct BboxRequest: Encodable {
        let minLat: Double
        let minLng: Double
        let maxLat: Double
        let maxLng: Double
        let dayOfWeek: Int?
        let hourOfDay: Int?
    }

    private struct RouteRequest: Encodable {
        let polyline: String
        let dayOfWeek: Int?
        let hourOfDay: Int?
        let departureTime: String?
        let widthMeters: Int?
    }
}
