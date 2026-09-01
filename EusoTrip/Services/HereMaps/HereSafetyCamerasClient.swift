//
//  HereSafetyCamerasClient.swift
//  EusoTrip — authenticated backend client for HERE Safety Cameras.
//
//  The backend attempts HERE Safety Cameras API v2 first. When that
//  separately licensed live feed is unavailable, it falls back to the
//  current Map Attributes v8 SAFETY_ALERTS layer for real static cameras.
//
//  Provider credentials and entitlement checks stay on the EusoTrip server.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

/// Safety camera entry. HERE tags fixed cameras with speed limit +
/// camera type (speed, red-light, combo) in the extended attributes
/// on a Browse result. We re-use the shared Browse wire types where
/// possible; camera-specific fields live on this lightweight model.
struct HereSafetyCameraItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let address: HereBrowseAddress?
    let position: HerePosition?
    let distance: Int?
    let categories: [HereBrowseCategory]?
    /// Present when HERE ships the speed-limit reference for the
    /// camera location. Miles per hour vs. km/h depends on the
    /// underlying road data.
    let speedLimit: Double?
    /// "speed" | "red_light" | "speed_red_light" | "section" | "mobile"
    let cameraType: String?
    let source: String?
    let liveFeedEntitled: Bool?
}

struct HereSafetyCamerasResponse: Decodable {
    let items: [HereSafetyCameraItem]
}

final class HereSafetyCamerasClient {
    static let shared = HereSafetyCamerasClient()

    init(session: URLSession = .shared) {
        _ = session
    }

    /// Safety cameras near a point, with live-feed entitlement and static
    /// Map Attributes coverage resolved by the authenticated backend.
    func camerasNearby(
        center: CLLocationCoordinate2D,
        limit: Int = 40
    ) async throws -> [HereSafetyCameraItem] {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: center.latitude,
            longitude: center.longitude
        ) else {
            throw HereMapsError.providerError("Location is unavailable.")
        }
        let result: BackendResult = try await EusoTripAPI.shared.query(
            "hereMaps.safetyCamerasAtResult",
            input: BackendRequest(
                at: BackendCoord(lat: coordinate.latitude, lng: coordinate.longitude),
                radiusMeters: 30_000
            )
        )
        guard result.available else {
            throw HereMapsError.providerError(
                result.error ?? "HERE safety camera coverage is unavailable."
            )
        }
        return Array(result.data.prefix(min(200, max(1, limit)))).compactMap { row in
            guard let position = LatLongParser.validatedCoordinate(
                latitude: row.lat,
                longitude: row.lng
            ) else { return nil }
            return HereSafetyCameraItem(
                id: row.id,
                title: row.roadName ?? "Safety camera",
                address: nil,
                position: HerePosition(
                    latitude: position.latitude,
                    longitude: position.longitude
                ),
                distance: row.distanceMeters,
                categories: nil,
                speedLimit: row.speedLimitMph,
                cameraType: row.type,
                source: row.source,
                liveFeedEntitled: result.liveFeedEntitled
            )
        }
    }

    private struct BackendCoord: Encodable {
        let lat: Double
        let lng: Double
    }

    private struct BackendRequest: Encodable {
        let at: BackendCoord
        let radiusMeters: Int
    }

    private struct BackendCamera: Decodable {
        let id: String
        let type: String
        let lat: Double
        let lng: Double
        let speedLimitMph: Double?
        let distanceMeters: Int?
        let roadName: String?
        let source: String?
    }

    private struct BackendResult: Decodable {
        let available: Bool
        let data: [BackendCamera]
        let error: String?
        let coverage: String
        let liveFeedEntitled: Bool?
    }
}
