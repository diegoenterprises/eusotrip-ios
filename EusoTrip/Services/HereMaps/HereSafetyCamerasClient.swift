//
//  HereSafetyCamerasClient.swift
//  EusoTrip — REST client for HERE Safety Cameras.
//
//  Endpoint:
//      GET https://browse.search.hereapi.com/v1/browse
//      with categories=900-9300-0001 (Speed Camera / Safety Camera)
//
//  HERE surfaces safety cameras via the same Browse Places API
//  used for EV + Parking. The dedicated Safety Cameras feed ships
//  mobile-camera pings on top — those require the premium
//  subscription. For fixed-camera coverage the Browse path is
//  sufficient and is the one uniform auth/query shape the rest of
//  this folder uses.
//
//  Required params:
//      at=<lat>,<lng>  OR  in=corridor:<flexible-polyline>;w=<meters>
//      categories=900-9300-0001
//
//  Auth: Bearer via HereBearerFetch.
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

    private let session: URLSession
    private let decoder = JSONDecoder()

    /// HERE category id for Speed Camera / Safety Camera POIs.
    static let categoryIdSafetyCamera = "900-9300-0001"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Safety cameras near a point. Default radius via the Browse
    /// `at` proximity with limit 40 is enough to cover a 30-mile
    /// ahead cone at highway speeds.
    func camerasNearby(
        center: CLLocationCoordinate2D,
        limit: Int = 40
    ) async throws -> [HereSafetyCameraItem] {
        var comps = URLComponents(string: "https://browse.search.hereapi.com/v1/browse")!
        comps.queryItems = [
            URLQueryItem(name: "at", value: "\(center.latitude),\(center.longitude)"),
            URLQueryItem(name: "categories", value: Self.categoryIdSafetyCamera),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = comps.url else { throw HereMapsError.badURL }

        let data = try await HereBearerFetch.data(for: url, session: session)
        do {
            return try decoder.decode(HereSafetyCamerasResponse.self, from: data).items
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }
}
