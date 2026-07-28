//
//  HereEVClient.swift
//  EusoTrip — authenticated backend client for HERE EV Charge Points.
//
//  Endpoint:
//      GET https://browse.search.hereapi.com/v1/browse
//      with categories=700-7600-0322 (EV Charging Station)
//      with show=ev for connector + power metadata
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
//      in=circle:<lat>,<lng>;r=<meters>
//
//  Provider credentials stay on the EusoTrip server.
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
    /// Present for EV stations when `show=ev` is requested.
    /// HERE Browse returns this under `extended.evStation`.
    let extended: HereBrowseExtended?

    var chargingStation: HereBrowseChargingStation? { extended?.evStation }
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

struct HereBrowseExtended: Decodable, Hashable {
    let evStation: HereBrowseChargingStation?
}

struct HereBrowseChargingStation: Decodable, Hashable {
    let connectors: [HereChargingConnector]?
    private let totalNumberOfConnectorsRaw: Int?

    var totalNumberOfConnectors: Int? {
        if let totalNumberOfConnectorsRaw { return totalNumberOfConnectorsRaw }
        let counts = connectors?.compactMap(\.numberOfConnectors) ?? []
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    private enum CodingKeys: String, CodingKey {
        case connectors
        case totalNumberOfConnectorsRaw = "totalNumberOfConnectors"
    }
}

struct HereChargingConnector: Decodable, Hashable {
    /// CCS | CHAdeMO | Type2 | Tesla | etc.
    let connectorType: HereChargingConnectorType?
    let powerFeedType: String?
    let supplierName: String?
    let maxPowerLevel: Double?
    let voltsRange: String?
    let ampsRange: String?
    let chargingPoint: HereChargingPoint?
    let chargeMode: String?
    let fee: Bool?
    let paymentMethods: [String]?

    var numberOfConnectors: Int? { chargingPoint?.numberOfConnectors }
}

struct HereChargingConnectorType: Decodable, Hashable {
    let id: String?
    let name: String?
}

struct HereChargingPoint: Decodable, Hashable {
    let numberOfConnectors: Int?
}

// MARK: - Client

final class HereEVClient {
    static let shared = HereEVClient()

    /// HERE category id for EV Charging Station.
    static let categoryIdEVCharging = "700-7600-0322"

    init(session: URLSession = .shared) {
        _ = session
    }

    func chargingStations(
        near center: CLLocationCoordinate2D,
        limit: Int = 30,
        radiusMeters: Int = 25_000
    ) async throws -> [HereBrowseItem] {
        let rows: [BackendRow] = try await EusoTripAPI.shared.query(
            "hereMaps.evChargers",
            input: BackendRequest(
                at: BackendCoord(lat: center.latitude, lng: center.longitude),
                radiusMeters: min(100_000, max(500, radiusMeters)),
                connectorType: nil,
                minPowerKw: nil,
                onlyAvailable: nil,
                limit: min(200, max(1, limit))
            )
        )
        return rows.compactMap(\.raw).filter { item in
            guard let position = item.position else { return false }
            return HereGeocodingClient.isSane(position.latitude, position.longitude)
        }
    }

    private struct BackendCoord: Encodable {
        let lat: Double
        let lng: Double
    }

    private struct BackendRequest: Encodable {
        let at: BackendCoord
        let radiusMeters: Int
        let connectorType: String?
        let minPowerKw: Double?
        let onlyAvailable: Bool?
        let limit: Int
    }

    private struct BackendRow: Decodable {
        let raw: HereBrowseItem?
    }
}
