//
//  HereParkingClient.swift
//  EusoTrip — REST client for HERE Parking.
//
//  Endpoint:
//      GET https://browse.search.hereapi.com/v1/browse
//      with categories=800-8400-0141 (Parking Lot)
//                     +800-8400-0135 (Parking Garage)
//                     +400-4100-0199 (Truck Stop / Truck Parking)
//
//  HERE exposes parking through the Browse Places API — on-street
//  parking metering, off-street parking lots, and truck-specific
//  truck-stop POIs each carry a distinct category id. When the
//  premium "real-time off-street parking availability" feed is
//  licensed for this tenant, the per-item `parking` extension
//  carries live space counts + pricing. If it isn't licensed we
//  still get the static POI + basic address/contact, which keeps
//  the "Plan my break" surface honest without faking availability.
//
//  Required params:
//      at=<lat>,<lng>
//      categories=<comma-separated ids>
//
//  Auth: Bearer via HereBearerFetch.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

/// Per-item parking extension returned on parking POIs when the
/// tenant's API key includes "HERE Dynamic Parking" access. Optional
/// throughout — decode leniently so static Browse rows still land.
struct HereBrowseParking: Decodable, Hashable {
    let availability: String?
    let totalSpaces: Int?
    let availableSpaces: Int?
    /// Truck-specific sub-inventory when the lot accepts Class 8.
    let truckSpaces: Int?
    let truckAvailableSpaces: Int?
    let prices: [HereParkingPrice]?
    let paymentMethods: [String]?
    let maxDurationMinutes: Int?
    /// Coarse POI attributes from the map data — whether the lot
    /// has lighting, surveillance, showers, restaurant, etc. Useful
    /// for HOS-break planning.
    let amenities: [String]?
}

struct HereParkingPrice: Decodable, Hashable {
    let amount: Double?
    let currency: String?
    let durationMinutes: Int?
    let description: String?
}

final class HereParkingClient {
    static let shared = HereParkingClient()

    private let session: URLSession
    private let decoder = JSONDecoder()

    /// Canonical HERE category ids for off-street parking + truck
    /// stops. We omit `on-street` by default because truck drivers
    /// rarely park on-street for HOS breaks; callers that want the
    /// full inventory can pass a custom `categories` list.
    static let defaultCategories: [String] = [
        "800-8400-0141", // Parking Lot
        "800-8400-0135", // Parking Garage
        "400-4100-0199", // Truck Stop / Truck Parking
    ]

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Off-street parking + truck stops near a point. Defaults are
    /// tuned for an HOS-break or "I need somewhere to park tonight"
    /// glance — 20 results, 40km radius via the `at` proximity.
    func parkingNearby(
        center: CLLocationCoordinate2D,
        categories: [String] = HereParkingClient.defaultCategories,
        limit: Int = 30
    ) async throws -> [HereBrowseParkingItem] {
        var comps = URLComponents(string: "https://browse.search.hereapi.com/v1/browse")!
        comps.queryItems = [
            URLQueryItem(name: "at", value: "\(center.latitude),\(center.longitude)"),
            URLQueryItem(name: "categories", value: categories.joined(separator: ",")),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = comps.url else { throw HereMapsError.badURL }

        let data = try await HereBearerFetch.data(for: url, session: session)
        do {
            return try decoder.decode(HereBrowseParkingResponse.self, from: data).items
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }
}

/// Browse response shape specialised to decode the optional
/// `parking` extension alongside the standard Browse fields. Split
/// from the generic `HereBrowseResponse` so the EV client (which
/// carries `chargingStation` instead) stays focused.
struct HereBrowseParkingResponse: Decodable {
    let items: [HereBrowseParkingItem]
}

struct HereBrowseParkingItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let address: HereBrowseAddress?
    let position: HerePosition?
    let access: [HerePosition]?
    let distance: Int?
    let categories: [HereBrowseCategory]?
    let contacts: [HereBrowseContact]?
    let openingHours: [HereBrowseOpeningHours]?
    let chains: [HereBrowseChain]?
    let parking: HereBrowseParking?
}
