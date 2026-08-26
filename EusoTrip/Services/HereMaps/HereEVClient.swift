//
//  HereEVClient.swift
//  EusoTrip — authenticated backend client for HERE EV Charge Points.
//
//  The backend uses Geocoding & Search Browse for discovery, then resolves the
//  returned place IDs through HERE EV Charge Points API v3 for live EVSE and
//  connector-group status, tariffs, and truck restrictions. Truck charging
//  uses category 700-7600-0323 and its separate HERE license.
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
    let liveDetails: HereEVLiveDetails?

    var chargingStation: HereBrowseChargingStation? { extended?.evStation }

    private enum CodingKeys: String, CodingKey {
        case id, title, resultType, address, position, access, distance
        case categories, contacts, openingHours, chains, extended
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resultType = try c.decodeIfPresent(String.self, forKey: .resultType)
        address = try c.decodeIfPresent(HereBrowseAddress.self, forKey: .address)
        position = try c.decodeIfPresent(HerePosition.self, forKey: .position)
        access = try c.decodeIfPresent([HerePosition].self, forKey: .access)
        distance = try c.decodeIfPresent(Int.self, forKey: .distance)
        categories = try c.decodeIfPresent([HereBrowseCategory].self, forKey: .categories)
        contacts = try c.decodeIfPresent([HereBrowseContact].self, forKey: .contacts)
        openingHours = try c.decodeIfPresent([HereBrowseOpeningHours].self, forKey: .openingHours)
        chains = try c.decodeIfPresent([HereBrowseChain].self, forKey: .chains)
        extended = try c.decodeIfPresent(HereBrowseExtended.self, forKey: .extended)
        liveDetails = nil

        let decodedID = try c.decodeIfPresent(String.self, forKey: .id)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let decodedID, !decodedID.isEmpty {
            id = decodedID
        } else if let position {
            id = "ev:\(position.latitude),\(position.longitude)"
        } else {
            id = "ev:unlocated"
        }

        let decodedTitle = try c.decodeIfPresent(String.self, forKey: .title)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let decodedTitle, !decodedTitle.isEmpty {
            title = decodedTitle
        } else {
            title = "Charging station"
        }
    }

    init(
        id: String,
        title: String,
        resultType: String?,
        address: HereBrowseAddress?,
        position: HerePosition?,
        access: [HerePosition]?,
        distance: Int?,
        categories: [HereBrowseCategory]?,
        contacts: [HereBrowseContact]?,
        openingHours: [HereBrowseOpeningHours]?,
        chains: [HereBrowseChain]?,
        extended: HereBrowseExtended?,
        liveDetails: HereEVLiveDetails?
    ) {
        self.id = id
        self.title = title
        self.resultType = resultType
        self.address = address
        self.position = position
        self.access = access
        self.distance = distance
        self.categories = categories
        self.contacts = contacts
        self.openingHours = openingHours
        self.chains = chains
        self.extended = extended
        self.liveDetails = liveDetails
    }
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

    init(connectors: [HereChargingConnector]?, totalNumberOfConnectors: Int?) {
        self.connectors = connectors
        self.totalNumberOfConnectorsRaw = totalNumberOfConnectors
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

struct HereEVLiveDetails: Decodable, Hashable {
    let availableConnectorCount: Int?
    let totalConnectorCount: Int?
    let availabilityKnown: Bool
    let statusUpdatedAt: String?
    let price: HereEVPrice?
    let tariffs: [HereEVTariff]
    let supportedVehicles: [String]
    let truckRestrictions: HereEVTruckRestrictions?
}

struct HereEVPrice: Decodable, Hashable {
    let currency: String
    let perKwh: Double?
    let perSession: Double?
}

struct HereEVTariff: Decodable, Hashable {
    let partner: String?
    let partnerId: String?
    let name: String?
    let type: String?
    let currency: String?
    let components: [Component]

    struct Component: Decodable, Hashable {
        let dimension: String
        let price: Double
        let vat: Double?
        let step: Double?
    }
}

struct HereEVTruckRestrictions: Decodable, Hashable {
    let truckAccess: [String]
    let hazardousGoodsRestricted: Bool?
    let noClearanceHeight: Bool?
    let trailerParking: Bool?
    let overnightParking: Bool?
    let amenities: [String]
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
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: center.latitude,
            longitude: center.longitude
        ) else {
            throw HereMapsError.providerError("Location is unavailable.")
        }
        let result: BackendResult = try await EusoTripAPI.shared.query(
            "hereMaps.evChargersResult",
            input: BackendRequest(
                at: BackendCoord(lat: coordinate.latitude, lng: coordinate.longitude),
                vehicleType: "truck",
                radiusMeters: min(100_000, max(500, radiusMeters)),
                connectorType: nil,
                minPowerKw: nil,
                onlyAvailable: nil,
                limit: min(100, max(1, limit))
            )
        )
        guard result.available else {
            throw HereMapsError.providerError(result.error ?? "HERE EV charging is unavailable.")
        }
        return result.data.compactMap(\.browseItem)
    }

    private struct BackendCoord: Encodable {
        let lat: Double
        let lng: Double
    }

    private struct BackendRequest: Encodable {
        let at: BackendCoord
        let vehicleType: String
        let radiusMeters: Int
        let connectorType: String?
        let minPowerKw: Double?
        let onlyAvailable: Bool?
        let limit: Int
    }

    private struct BackendResult: Decodable {
        let available: Bool
        let data: [BackendRow]
        let error: String?
    }

    private struct BackendConnector: Decodable {
        let type: String
        let powerKw: Double?
        let totalCount: Int?
        let availableCount: Int?
        let statusUpdatedAt: String?
    }

    private struct BackendRow: Decodable {
        let id: String
        let name: String
        let operatorName: String?
        let lat: Double
        let lng: Double
        let address: String?
        let connectors: [BackendConnector]
        let distanceMeters: Double?
        let price: HereEVPrice?
        let tariffs: [HereEVTariff]?
        let totalConnectorCount: Int?
        let availableConnectorCount: Int?
        let availabilityKnown: Bool?
        let supportedVehicles: [String]?
        let truckRestrictions: HereEVTruckRestrictions?
        let raw: HereBrowseItem?

        private enum CodingKeys: String, CodingKey {
            case id, name, lat, lng, address, connectors, distanceMeters, price
            case tariffs, totalConnectorCount, availableConnectorCount
            case availabilityKnown, supportedVehicles, truckRestrictions, raw
            case operatorName = "operator"
        }

        var browseItem: HereBrowseItem? {
            guard let coordinate = LatLongParser.validatedCoordinate(
                latitude: lat,
                longitude: lng
            ) else { return nil }
            let normalizedConnectors = connectors.map { connector in
                HereChargingConnector(
                    connectorType: HereChargingConnectorType(id: nil, name: connector.type),
                    powerFeedType: nil,
                    supplierName: operatorName,
                    maxPowerLevel: connector.powerKw,
                    voltsRange: nil,
                    ampsRange: nil,
                    chargingPoint: HereChargingPoint(numberOfConnectors: connector.totalCount),
                    chargeMode: nil,
                    fee: price != nil,
                    paymentMethods: nil
                )
            }
            let station = HereBrowseChargingStation(
                connectors: normalizedConnectors,
                totalNumberOfConnectors: totalConnectorCount
            )
            let updatedAt = connectors.compactMap(\.statusUpdatedAt).sorted().last
            let details = HereEVLiveDetails(
                availableConnectorCount: availableConnectorCount,
                totalConnectorCount: totalConnectorCount,
                availabilityKnown: availabilityKnown ?? false,
                statusUpdatedAt: updatedAt,
                price: price,
                tariffs: tariffs ?? [],
                supportedVehicles: supportedVehicles ?? [],
                truckRestrictions: truckRestrictions
            )
            return HereBrowseItem(
                id: id,
                title: name,
                resultType: raw?.resultType,
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
                distance: distanceMeters.map { Int($0.rounded()) },
                categories: raw?.categories,
                contacts: raw?.contacts,
                openingHours: raw?.openingHours,
                chains: raw?.chains ?? operatorName.map {
                    [HereBrowseChain(id: "here-ev-operator", name: $0)]
                },
                extended: HereBrowseExtended(evStation: station),
                liveDetails: details
            )
        }
    }
}
