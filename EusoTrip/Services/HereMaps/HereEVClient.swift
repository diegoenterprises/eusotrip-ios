//
//  HereEVClient.swift
//  EusoTrip — REST client for HERE EV Charge Points.
//
//  Endpoint:
//      GET https://browse.search.hereapi.com/v1/browse
//      with categories=700-7600-0322 (EV Charging Station)
//
//  HERE's EV Products exposes charging stations through both a
//  dedicated `/ev/stations` feed and the Browse Places API keyed by
//  the canonical category id. We use Browse here because it uses
//  the same bearer auth + query shape as Parking / Safety Cameras
//  in this codebase, keeping the client surface uniform. When the
//  iOS app earns access to the premium real-time connector
//  availability feed, swap the `eV` accessor to the dedicated
//  endpoint without touching callers.
//
//  Required params:
//      at=<lat>,<lng>
//      categories=700-7600-0322
//
//  Optional:
//      limit=<N>
//      in=circle:<lat>,<lng>;r=<meters>     (alternative to `at`)
//
//  Auth: Bearer via HereBearerFetch.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

// MARK: - Wire types (HERE Browse)

struct HereBrowseResponse: Decodable {
    let items: [HereBrowseItem]
}

struct HereBrowseItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let resultType: String?
    let address: HereBrowseAddress?
    let position: HerePosition?
    let access: [HerePosition]?
    let distance: Int?
    let categories: [HereBrowseCategory]?
    let contacts: [HereBrowseContact]?
    let openingHours: [HereBrowseOpeningHours]?
    let chains: [HereBrowseChain]?
    /// Present for EV stations — HERE ships a `chargingStation`
    /// extension on qualifying POIs with connectors + power info.
    let chargingStation: HereBrowseChargingStation?
}

struct HereBrowseAddress: Decodable, Hashable {
    let label: String?
    let city: String?
    let state: String?
    let stateCode: String?
    let countryCode: String?
    let postalCode: String?
    let street: String?
    let houseNumber: String?
}

struct HereBrowseCategory: Decodable, Hashable {
    let id: String
    let name: String?
    let primary: Bool?
}

struct HereBrowseContact: Decodable, Hashable {
    struct Entry: Decodable, Hashable {
        let label: String?
        let value: String?
    }
    let phone: [Entry]?
    let www: [Entry]?
    let email: [Entry]?
}

struct HereBrowseOpeningHours: Decodable, Hashable {
    let text: [String]?
    let isOpen: Bool?
}

struct HereBrowseChain: Decodable, Hashable {
    let id: String
    let name: String?
}

// MARK: - EV charging extension

struct HereBrowseChargingStation: Decodable, Hashable {
    let connectors: [HereChargingConnector]?
    let totalNumberOfConnectors: Int?
}

struct HereChargingConnector: Decodable, Hashable {
    /// CCS | CHAdeMO | Type2 | Tesla | etc.
    let connectorType: HereChargingConnectorType?
    let powerFeedType: String?
    let supplierName: String?
    let maxPowerLevel: Double?
    let voltsRange: String?
    let ampsRange: String?
    let numberOfConnectors: Int?
    let chargeMode: String?
    let fee: Bool?
    let paymentMethods: [String]?
}

struct HereChargingConnectorType: Decodable, Hashable {
    let id: String?
    let name: String?
}

// MARK: - Client

final class HereEVClient {
    static let shared = HereEVClient()

    private let session: URLSession
    private let decoder = JSONDecoder()

    /// HERE category id for EV Charging Station.
    static let categoryIdEVCharging = "700-7600-0322"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func chargingStations(
        near center: CLLocationCoordinate2D,
        limit: Int = 30
    ) async throws -> [HereBrowseItem] {
        var comps = URLComponents(string: "https://browse.search.hereapi.com/v1/browse")!
        comps.queryItems = [
            URLQueryItem(name: "at", value: "\(center.latitude),\(center.longitude)"),
            URLQueryItem(name: "categories", value: Self.categoryIdEVCharging),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = comps.url else { throw HereMapsError.badURL }

        let data = try await HereBearerFetch.data(for: url, session: session)
        do {
            return try decoder.decode(HereBrowseResponse.self, from: data).items
        } catch {
            throw HereMapsError.decoding(String(describing: error))
        }
    }
}
