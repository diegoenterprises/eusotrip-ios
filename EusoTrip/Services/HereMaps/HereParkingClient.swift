//
//  HereParkingClient.swift
//  EusoTrip — authenticated backend client for HERE Parking.
//
//  Endpoint:
//      GET https://browse.search.hereapi.com/v1/browse
//      with categories=800-8500      (Parking family)
//                     +700-7900-0131 (Truck & Trailer Parking)
//                     +700-7900-0132 (Truck Stop / Plaza)
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
//  Provider credentials stay on the EusoTrip server.
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

    /// Canonical HERE category ids for off-street parking + truck
    /// parking. 2026-06-09: the previous ids (800-8400-*, 400-4100-0199)
    /// belong to retired families — Browse answers them with a silent
    /// `{"items":[]}` (no error!), which is why the parking layer never
    /// showed a single pin. Live-probed canon: 800-8500 is the parking
    /// family (0178 Parking Lot et al.), 700-7900-0131 is Truck &
    /// Trailer Parking, 700-7900-0132 is Truck Stop/Plaza.
    static let defaultCategories: [String] = [
        "800-8500",      // Parking family (lot / garage / on+off street)
        "700-7900-0131", // Truck & Trailer Parking
        "700-7900-0132", // Truck Stop - Plaza
    ]

    init(session: URLSession = .shared) {
        _ = session
    }

    /// Off-street parking + truck stops near a point. Defaults are
    /// tuned for an HOS-break or "I need somewhere to park tonight"
    /// glance — 20 results, 40km radius via the `at` proximity.
    func parkingNearby(
        center: CLLocationCoordinate2D,
        categories: [String] = HereParkingClient.defaultCategories,
        limit: Int = 30
    ) async throws -> [HereBrowseParkingItem] {
        _ = categories
        let rows: [BackendRow] = try await EusoTripAPI.shared.query(
            "hereMaps.parkingNearby",
            input: BackendRequest(
                at: BackendCoord(lat: center.latitude, lng: center.longitude),
                radiusMeters: 40_000,
                truckOnly: true
            )
        )
        return Array(rows.compactMap(\.raw).prefix(min(50, max(1, limit))))
    }

    private struct BackendCoord: Encodable {
        let lat: Double
        let lng: Double
    }

    private struct BackendRequest: Encodable {
        let at: BackendCoord
        let radiusMeters: Int
        let truckOnly: Bool
    }

    private struct BackendRow: Decodable {
        let raw: HereBrowseParkingItem?
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
