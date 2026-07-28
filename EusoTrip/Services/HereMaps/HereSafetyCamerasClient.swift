//
//  HereSafetyCamerasClient.swift
//  EusoTrip — authenticated backend client for HERE Safety Cameras.
//
//  Endpoint:
//      GET https://browse.search.hereapi.com/v1/browse
//      with categories=900-9300-0001 (Speed Camera / Safety Camera)
//
//  HERE has not provisioned the Safety Cameras data product on this
//  account yet. Browse category probes for 900-9300-0001 return an
//  honest empty set on the live enterprise key, so this client keeps
//  the stable query shape and lets the add-on layer fail soft rather
//  than fabricating camera pins.
//
//  Required params:
//      at=<lat>,<lng>  OR  in=corridor:<flexible-polyline>;w=<meters>
//      categories=900-9300-0001
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
}

struct HereSafetyCamerasResponse: Decodable {
    let items: [HereSafetyCameraItem]
}

final class HereSafetyCamerasClient {
    static let shared = HereSafetyCamerasClient()

    /// HERE category id for Speed Camera / Safety Camera POIs.
    ///
    /// 2026-06-09 reality check (live-probed ATL / DC / CDMX / London):
    /// Browse has NO populated safety-camera POI category — this id
    /// returns `{"items":[]}` everywhere, and the 900-9300 family is
    /// unrelated POIs. Cameras ship in HERE's dedicated Safety Cameras
    /// data product (separate entitlement), not Places. Until that
    /// product is wired, this layer stays honestly empty (the add-on
    /// fail-soft hides the pins + chip rather than faking them).
    static let categoryIdSafetyCamera = "900-9300-0001"

    init(session: URLSession = .shared) {
        _ = session
    }

    /// Safety cameras near a point. Default radius via the Browse
    /// `at` proximity with limit 40 is enough to cover a 30-mile
    /// ahead cone at highway speeds.
    func camerasNearby(
        center: CLLocationCoordinate2D,
        limit: Int = 40
    ) async throws -> [HereSafetyCameraItem] {
        let status: BackendStatus = try await EusoTripAPI.shared.queryNoInput(
            "hereMaps.status"
        )
        guard status.products.safetyCameras else {
            throw HereMapsError.providerError(
                "HERE Safety Cameras is not licensed for this account."
            )
        }
        let rows: [BackendCamera] = try await EusoTripAPI.shared.query(
            "hereMaps.safetyCamerasAt",
            input: BackendRequest(
                at: BackendCoord(lat: center.latitude, lng: center.longitude),
                radiusMeters: 30_000
            )
        )
        return Array(rows.prefix(min(200, max(1, limit)))).map { row in
            HereSafetyCameraItem(
                id: row.id,
                title: row.roadName ?? "Safety camera",
                address: nil,
                position: HerePosition(latitude: row.lat, longitude: row.lng),
                distance: row.distanceMeters,
                categories: nil,
                speedLimit: row.speedLimitMph,
                cameraType: row.type
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
    }

    private struct BackendStatus: Decodable {
        let products: Products

        struct Products: Decodable {
            let safetyCameras: Bool
        }
    }
}
