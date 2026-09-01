//
//  HereParkingClient.swift
//  EusoTrip — authenticated backend client for HERE Parking.
//
//  The backend composes HERE Search Browse discovery with Map Attributes v8
//  TRUCK_PARKING_POI/TRUCK_PARKING_POI_STATUS. Premium Off-Street Parking v2
//  enriches general facilities when the account is entitled. No provider
//  credentials or premium endpoint calls leave the EusoTrip server.
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
    let availabilityUpdatedAt: String?
    let availabilityTrend: String?
    let freeParking: Bool?
    let secureParking: Bool?
    let reservable: Bool?
    let maxHeightMeters: Double?
    let maxLengthMeters: Double?
    let source: String?
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
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: center.latitude,
            longitude: center.longitude
        ) else {
            throw HereMapsError.providerError("Location is unavailable.")
        }
        let result: BackendResult = try await EusoTripAPI.shared.query(
            "hereMaps.parkingNearbyResult",
            input: BackendRequest(
                at: BackendCoord(lat: coordinate.latitude, lng: coordinate.longitude),
                radiusMeters: 40_000,
                truckOnly: true
            )
        )
        guard result.available else {
            throw HereMapsError.providerError(result.error ?? "HERE parking is unavailable.")
        }
        let validItems = result.data.compactMap(\.browseItem)
        return Array(validItems.prefix(min(50, max(1, limit))))
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

    private struct BackendResult: Decodable {
        let available: Bool
        let data: [BackendRow]
        let error: String?
    }

    private struct BackendRow: Decodable {
        let id: String
        let name: String
        let address: String?
        let lat: Double
        let lng: Double
        let distanceMeters: Int?
        let availableSpaces: Int?
        let totalSpaces: Int?
        let availabilityUpdatedAt: String?
        let availabilityTrend: String?
        let hourlyRate: Double?
        let currency: String?
        let maxHeightMeters: Double?
        let maxLengthMeters: Double?
        let openNow: Bool?
        let freeParking: Bool?
        let secureParking: Bool?
        let reservable: Bool?
        let amenities: [String]
        let source: String
        let raw: HereBrowseParkingItem?

        var browseItem: HereBrowseParkingItem? {
            guard let coordinate = LatLongParser.validatedCoordinate(
                latitude: lat,
                longitude: lng
            ) else { return nil }
            let price = hourlyRate.map {
                HereParkingPrice(
                    amount: $0,
                    currency: currency,
                    durationMinutes: 60,
                    description: nil
                )
            }
            let normalizedParking = HereBrowseParking(
                availability: availableSpaces == nil ? nil : "AVAILABLE",
                totalSpaces: totalSpaces,
                availableSpaces: availableSpaces,
                truckSpaces: totalSpaces,
                truckAvailableSpaces: availableSpaces,
                prices: price.map { [$0] },
                paymentMethods: raw?.parking?.paymentMethods,
                maxDurationMinutes: raw?.parking?.maxDurationMinutes,
                amenities: amenities.isEmpty ? raw?.parking?.amenities : amenities,
                availabilityUpdatedAt: availabilityUpdatedAt,
                availabilityTrend: availabilityTrend,
                freeParking: freeParking,
                secureParking: secureParking,
                reservable: reservable,
                maxHeightMeters: maxHeightMeters,
                maxLengthMeters: maxLengthMeters,
                source: source
            )
            return HereBrowseParkingItem(
                id: id,
                title: name,
                address: raw?.address ?? HereBrowseAddress(
                    label: address,
                    city: nil,
                    state: nil,
                    stateCode: nil,
                    countryCode: nil,
                    postalCode: nil,
                    street: nil,
                    houseNumber: nil
                ),
                position: HerePosition(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                access: raw?.access,
                distance: distanceMeters,
                categories: raw?.categories,
                contacts: raw?.contacts,
                openingHours: raw?.openingHours,
                chains: raw?.chains,
                parking: normalizedParking,
                openNow: openNow
            )
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
    let openNow: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, title, address, position, access, distance, categories
        case contacts, openingHours, chains, parking, openNow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decodeIfPresent(HereBrowseAddress.self, forKey: .address)
        position = try c.decodeIfPresent(HerePosition.self, forKey: .position)
        access = try c.decodeIfPresent([HerePosition].self, forKey: .access)
        distance = try c.decodeIfPresent(Int.self, forKey: .distance)
        categories = try c.decodeIfPresent([HereBrowseCategory].self, forKey: .categories)
        contacts = try c.decodeIfPresent([HereBrowseContact].self, forKey: .contacts)
        openingHours = try c.decodeIfPresent([HereBrowseOpeningHours].self, forKey: .openingHours)
        chains = try c.decodeIfPresent([HereBrowseChain].self, forKey: .chains)
        parking = try c.decodeIfPresent(HereBrowseParking.self, forKey: .parking)
        openNow = try c.decodeIfPresent(Bool.self, forKey: .openNow)

        let decodedID = try c.decodeIfPresent(String.self, forKey: .id)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let decodedID, !decodedID.isEmpty {
            id = decodedID
        } else if let position {
            id = "parking:\(position.latitude),\(position.longitude)"
        } else {
            id = "parking:unlocated"
        }

        let decodedTitle = try c.decodeIfPresent(String.self, forKey: .title)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let decodedTitle, !decodedTitle.isEmpty {
            title = decodedTitle
        } else {
            title = "Parking"
        }
    }

    init(
        id: String,
        title: String,
        address: HereBrowseAddress?,
        position: HerePosition?,
        access: [HerePosition]?,
        distance: Int?,
        categories: [HereBrowseCategory]?,
        contacts: [HereBrowseContact]?,
        openingHours: [HereBrowseOpeningHours]?,
        chains: [HereBrowseChain]?,
        parking: HereBrowseParking?,
        openNow: Bool?
    ) {
        self.id = id
        self.title = title
        self.address = address
        self.position = position
        self.access = access
        self.distance = distance
        self.categories = categories
        self.contacts = contacts
        self.openingHours = openingHours
        self.chains = chains
        self.parking = parking
        self.openNow = openNow
    }
}
