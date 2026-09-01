//
//  OfflineRouteModels.swift
//  EusoTrip
//
//  Foundation-only contracts for offline search and road routing. Rail and
//  vessel geometry remains server-canonical by design.
//

import Foundation

/// Non-empty, unique attribution from a trusted installed-region resolver.
/// A HERE cache hit or merely having some region installed is never enough to
/// construct this evidence; callers must prove which installed regions cover
/// the search area or complete route corridor.
struct OfflineInstalledCoverageEvidence: Hashable, Codable, Sendable {
    let regionIDs: [OfflineMapRegionID]

    init(regionIDs: [OfflineMapRegionID]) throws {
        guard !regionIDs.isEmpty else {
            throw OfflineMapCoreError.invalidInput(
                "Installed-region coverage evidence cannot be empty."
            )
        }
        guard Set(regionIDs).count == regionIDs.count else {
            throw OfflineMapCoreError.invalidInput(
                "Installed-region coverage evidence must contain unique regions."
            )
        }
        self.regionIDs = regionIDs
    }

    private enum CodingKeys: String, CodingKey { case regionIDs }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                regionIDs: container.decode([OfflineMapRegionID].self, forKey: .regionIDs)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .regionIDs,
                in: container,
                debugDescription: "Installed-region coverage evidence is invalid."
            )
        }
    }
}

struct OfflineGeoCoordinate: Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, (-90 ... 90).contains(latitude) else {
            throw OfflineMapCoreError.invalidInput("Latitude must be between -90 and 90 degrees.")
        }
        guard longitude.isFinite, (-180 ... 180).contains(longitude) else {
            throw OfflineMapCoreError.invalidInput("Longitude must be between -180 and 180 degrees.")
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        do {
            try self.init(latitude: latitude, longitude: longitude)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .latitude,
                in: container,
                debugDescription: "Invalid geographic coordinate."
            )
        }
    }
}

enum RoutePlanProvenance: String, Codable, Sendable {
    /// Tenant-authorized `route.plan` output. This remains authoritative for
    /// freight execution and is the only allowed source for rail/vessel paths.
    case serverCanonical
    /// A route calculated on-device from installed HERE map data.
    case hereOfflineLocal
}

enum OfflineRouteMode: String, Codable, Sendable, CaseIterable {
    case road
    case truck
    case rail
    case vessel

    var supportsHEREOfflineCalculation: Bool {
        switch self {
        case .road, .truck:
            return true
        case .rail, .vessel:
            return false
        }
    }
}

struct OfflineRouteWaypoint: Hashable, Codable, Sendable {
    let coordinate: OfflineGeoCoordinate
    let label: String?

    init(coordinate: OfflineGeoCoordinate, label: String? = nil) {
        self.coordinate = coordinate
        self.label = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

enum OfflineHazardousGoodsClass: String, Codable, Sendable, CaseIterable {
    case explosive
    case gas
    case flammable
    case combustible
    case organic
    case poison
    case radioActive
    case corrosive
    case poisonousInhalation
    case harmfulToWater
    case other
}

/// Explicit SDK-independent truck identity. The adapter must map these values
/// to HERE and must fail if a future SDK cannot represent the selected value.
enum OfflineTruckType: String, Codable, Sendable, CaseIterable {
    case straight
    case tractor
}

enum OfflineTruckCategory: String, Codable, Sendable, CaseIterable {
    case straight
    case tractor
}

enum OfflineTruckTunnelCategory: String, Codable, Sendable, CaseIterable {
    case b
    case c
    case d
    case e
}

struct OfflineTruckConstraints: Hashable, Codable, Sendable {
    /// Required so the adapter never silently defaults to a HERE truck type.
    let truckType: OfflineTruckType
    /// Required so the adapter never silently defaults to a HERE restriction category.
    let truckCategory: OfflineTruckCategory
    let tunnelCategory: OfflineTruckTunnelCategory?
    let grossWeightKilograms: Int?
    let weightPerAxleKilograms: Int?
    let heightCentimeters: Int?
    let widthCentimeters: Int?
    let lengthCentimeters: Int?
    let axleCount: Int?
    let trailerCount: Int?
    let hazardousGoods: Set<OfflineHazardousGoodsClass>

    init(
        truckType: OfflineTruckType,
        truckCategory: OfflineTruckCategory,
        tunnelCategory: OfflineTruckTunnelCategory? = nil,
        grossWeightKilograms: Int? = nil,
        weightPerAxleKilograms: Int? = nil,
        heightCentimeters: Int? = nil,
        widthCentimeters: Int? = nil,
        lengthCentimeters: Int? = nil,
        axleCount: Int? = nil,
        trailerCount: Int? = nil,
        hazardousGoods: Set<OfflineHazardousGoodsClass> = []
    ) throws {
        let positiveValues = [
            grossWeightKilograms,
            weightPerAxleKilograms,
            heightCentimeters,
            widthCentimeters,
            lengthCentimeters,
            axleCount
        ]
        guard positiveValues.compactMap({ $0 }).allSatisfy({ $0 > 0 }) else {
            throw OfflineMapCoreError.invalidInput("Truck dimensions, weights, and axle count must be positive.")
        }
        if let trailerCount, trailerCount < 0 {
            throw OfflineMapCoreError.invalidInput("Trailer count cannot be negative.")
        }
        self.truckType = truckType
        self.truckCategory = truckCategory
        self.tunnelCategory = tunnelCategory
        self.grossWeightKilograms = grossWeightKilograms
        self.weightPerAxleKilograms = weightPerAxleKilograms
        self.heightCentimeters = heightCentimeters
        self.widthCentimeters = widthCentimeters
        self.lengthCentimeters = lengthCentimeters
        self.axleCount = axleCount
        self.trailerCount = trailerCount
        self.hazardousGoods = hazardousGoods
    }

    private enum CodingKeys: String, CodingKey {
        case truckType, truckCategory, tunnelCategory, grossWeightKilograms
        case weightPerAxleKilograms, heightCentimeters, widthCentimeters
        case lengthCentimeters, axleCount, trailerCount, hazardousGoods
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                truckType: container.decode(OfflineTruckType.self, forKey: .truckType),
                truckCategory: container.decode(OfflineTruckCategory.self, forKey: .truckCategory),
                tunnelCategory: container.decodeIfPresent(OfflineTruckTunnelCategory.self, forKey: .tunnelCategory),
                grossWeightKilograms: container.decodeIfPresent(Int.self, forKey: .grossWeightKilograms),
                weightPerAxleKilograms: container.decodeIfPresent(Int.self, forKey: .weightPerAxleKilograms),
                heightCentimeters: container.decodeIfPresent(Int.self, forKey: .heightCentimeters),
                widthCentimeters: container.decodeIfPresent(Int.self, forKey: .widthCentimeters),
                lengthCentimeters: container.decodeIfPresent(Int.self, forKey: .lengthCentimeters),
                axleCount: container.decodeIfPresent(Int.self, forKey: .axleCount),
                trailerCount: container.decodeIfPresent(Int.self, forKey: .trailerCount),
                hazardousGoods: container.decode(Set<OfflineHazardousGoodsClass>.self, forKey: .hazardousGoods)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .truckType,
                in: container,
                debugDescription: "Offline truck constraints are invalid."
            )
        }
    }
}

struct OfflineRouteRequest: Sendable {
    let id: UUID
    let waypoints: [OfflineRouteWaypoint]
    let mode: OfflineRouteMode
    let truckConstraints: OfflineTruckConstraints?
    let departureTime: Date?

    init(
        id: UUID = UUID(),
        waypoints: [OfflineRouteWaypoint],
        mode: OfflineRouteMode,
        truckConstraints: OfflineTruckConstraints? = nil,
        departureTime: Date? = nil
    ) throws {
        guard waypoints.count >= 2 else {
            throw OfflineMapCoreError.invalidInput("An offline route needs at least two waypoints.")
        }
        guard mode.supportsHEREOfflineCalculation else {
            throw OfflineMapCoreError.unsupportedLocalRouting(mode)
        }
        if mode == .truck, truckConstraints == nil {
            throw OfflineMapCoreError.invalidInput("Truck routing requires an explicit truck profile.")
        }
        if mode != .truck, truckConstraints != nil {
            throw OfflineMapCoreError.invalidInput("Truck constraints can only be used for truck routes.")
        }
        self.id = id
        self.waypoints = waypoints
        self.mode = mode
        self.truckConstraints = truckConstraints
        self.departureTime = departureTime
    }
}

enum OfflineRouteTrafficBasis: String, Codable, Sendable {
    /// No live or historical traffic promise is made while radio-silent.
    case noneOffline
}

struct OfflineRouteSummary: Hashable, Codable, Sendable {
    let distanceMeters: Int64
    let durationSeconds: Int64
    let trafficBasis: OfflineRouteTrafficBasis

    init(distanceMeters: Int64, durationSeconds: Int64) throws {
        guard distanceMeters >= 0, durationSeconds >= 0 else {
            throw OfflineMapCoreError.invalidInput("Route distance and duration cannot be negative.")
        }
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.trafficBasis = .noneOffline
    }

    private enum CodingKeys: String, CodingKey {
        case distanceMeters, durationSeconds, trafficBasis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let trafficBasis = try container.decode(OfflineRouteTrafficBasis.self, forKey: .trafficBasis)
        guard trafficBasis == .noneOffline else {
            throw DecodingError.dataCorruptedError(
                forKey: .trafficBasis,
                in: container,
                debugDescription: "An offline route cannot claim a traffic basis."
            )
        }
        do {
            try self.init(
                distanceMeters: container.decode(Int64.self, forKey: .distanceMeters),
                durationSeconds: container.decode(Int64.self, forKey: .durationSeconds)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .distanceMeters,
                in: container,
                debugDescription: "Offline route summary is invalid."
            )
        }
    }
}

struct OfflineRouteManeuver: Hashable, Codable, Sendable {
    let sequence: Int
    let instruction: String
    let coordinate: OfflineGeoCoordinate
    let distanceFromStartMeters: Int64?

    init(
        sequence: Int,
        instruction: String,
        coordinate: OfflineGeoCoordinate,
        distanceFromStartMeters: Int64?
    ) throws {
        guard sequence >= 0 else {
            throw OfflineMapCoreError.invalidInput("Maneuver sequence cannot be negative.")
        }
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineMapCoreError.invalidInput("A maneuver instruction cannot be empty.")
        }
        if let distanceFromStartMeters, distanceFromStartMeters < 0 {
            throw OfflineMapCoreError.invalidInput("Maneuver distance cannot be negative.")
        }
        self.sequence = sequence
        self.instruction = instruction
        self.coordinate = coordinate
        self.distanceFromStartMeters = distanceFromStartMeters
    }

    private enum CodingKeys: String, CodingKey {
        case sequence, instruction, coordinate, distanceFromStartMeters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sequence: container.decode(Int.self, forKey: .sequence),
                instruction: container.decode(String.self, forKey: .instruction),
                coordinate: container.decode(OfflineGeoCoordinate.self, forKey: .coordinate),
                distanceFromStartMeters: container.decodeIfPresent(Int64.self, forKey: .distanceFromStartMeters)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .instruction,
                in: container,
                debugDescription: "Offline route maneuver is invalid."
            )
        }
    }
}

struct OfflineRouteSection: Hashable, Codable, Sendable {
    let coordinates: [OfflineGeoCoordinate]
    let maneuvers: [OfflineRouteManeuver]
    let summary: OfflineRouteSummary

    init(
        coordinates: [OfflineGeoCoordinate],
        maneuvers: [OfflineRouteManeuver],
        summary: OfflineRouteSummary
    ) throws {
        guard coordinates.count >= 2 else {
            throw OfflineMapCoreError.invalidInput("An offline route section needs at least two coordinates.")
        }
        let sequences = maneuvers.map(\.sequence)
        guard sequences == sequences.sorted(), Set(sequences).count == sequences.count else {
            throw OfflineMapCoreError.invalidInput("Maneuvers must have unique, ascending sequence numbers.")
        }
        self.coordinates = coordinates
        self.maneuvers = maneuvers
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case coordinates, maneuvers, summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                coordinates: container.decode([OfflineGeoCoordinate].self, forKey: .coordinates),
                maneuvers: container.decode([OfflineRouteManeuver].self, forKey: .maneuvers),
                summary: container.decode(OfflineRouteSummary.self, forKey: .summary)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .coordinates,
                in: container,
                debugDescription: "Offline route section is invalid."
            )
        }
    }
}

struct OfflineLocalRoute: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let mode: OfflineRouteMode
    let sections: [OfflineRouteSection]
    let summary: OfflineRouteSummary
    let notices: [String]
    let provenance: RoutePlanProvenance
    let coverage: OfflineInstalledCoverageEvidence

    init(
        id: String,
        mode: OfflineRouteMode,
        sections: [OfflineRouteSection],
        summary: OfflineRouteSummary,
        notices: [String],
        coverage: OfflineInstalledCoverageEvidence
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineMapCoreError.invalidInput("An offline route identifier cannot be empty.")
        }
        guard mode.supportsHEREOfflineCalculation else {
            throw OfflineMapCoreError.unsupportedLocalRouting(mode)
        }
        guard !sections.isEmpty else {
            throw OfflineMapCoreError.invalidInput("An offline route must contain geometry.")
        }
        self.id = id
        self.mode = mode
        self.sections = sections
        self.summary = summary
        self.notices = notices.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.provenance = .hereOfflineLocal
        self.coverage = coverage
    }

    private enum CodingKeys: String, CodingKey {
        case id, mode, sections, summary, notices, provenance, coverage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provenance = try container.decode(RoutePlanProvenance.self, forKey: .provenance)
        guard provenance == .hereOfflineLocal else {
            throw DecodingError.dataCorruptedError(
                forKey: .provenance,
                in: container,
                debugDescription: "An offline local route must have HERE offline-local provenance."
            )
        }
        try self.init(
            id: container.decode(String.self, forKey: .id),
            mode: container.decode(OfflineRouteMode.self, forKey: .mode),
            sections: container.decode([OfflineRouteSection].self, forKey: .sections),
            summary: container.decode(OfflineRouteSummary.self, forKey: .summary),
            notices: container.decode([String].self, forKey: .notices),
            coverage: container.decode(OfflineInstalledCoverageEvidence.self, forKey: .coverage)
        )
    }
}

struct OfflineRouteResponse: Sendable {
    let requestID: UUID
    let routes: [OfflineLocalRoute]
    let coverage: OfflineInstalledCoverageEvidence
    let calculatedAt: Date

    var coveredByRegionIDs: [OfflineMapRegionID] { coverage.regionIDs }

    init(
        requestID: UUID,
        routes: [OfflineLocalRoute],
        coverage: OfflineInstalledCoverageEvidence,
        calculatedAt: Date = Date()
    ) throws {
        guard !routes.isEmpty else {
            throw OfflineMapCoreError.invalidInput("The offline routing engine returned no route.")
        }
        let responseRegionIDs = Set(coverage.regionIDs)
        guard routes.allSatisfy({ Set($0.coverage.regionIDs).isSubset(of: responseRegionIDs) }) else {
            throw OfflineMapCoreError.invalidInput(
                "Every offline route must carry corridor coverage within the response evidence."
            )
        }
        self.requestID = requestID
        self.routes = routes
        self.coverage = coverage
        self.calculatedAt = calculatedAt
    }
}

struct OfflineSearchRequest: Sendable {
    let text: String
    /// Required so HERE never invents a search area or silently expands from
    /// installed data into an online/global query.
    let center: OfflineGeoCoordinate
    let maximumResultCount: Int

    init(text: String, center: OfflineGeoCoordinate, maximumResultCount: Int = 20) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OfflineMapCoreError.invalidInput("Offline search text cannot be empty.")
        }
        guard (1 ... 100).contains(maximumResultCount) else {
            throw OfflineMapCoreError.invalidInput("Offline search result count must be between 1 and 100.")
        }
        self.text = text
        self.center = center
        self.maximumResultCount = maximumResultCount
    }
}

struct OfflineSearchResult: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let address: String?
    let coordinate: OfflineGeoCoordinate
    let categories: [String]
    let regionID: OfflineMapRegionID
    let provenance: RoutePlanProvenance

    init(
        id: String,
        title: String,
        address: String?,
        coordinate: OfflineGeoCoordinate,
        categories: [String],
        regionID: OfflineMapRegionID
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineMapCoreError.invalidInput("An offline search result identifier cannot be empty.")
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OfflineMapCoreError.invalidInput("An offline search result title cannot be empty.")
        }
        self.id = id
        self.title = title
        self.address = address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.coordinate = coordinate
        self.categories = categories.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.regionID = regionID
        self.provenance = .hereOfflineLocal
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, address, coordinate, categories, regionID, provenance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provenance = try container.decode(RoutePlanProvenance.self, forKey: .provenance)
        guard provenance == .hereOfflineLocal else {
            throw DecodingError.dataCorruptedError(
                forKey: .provenance,
                in: container,
                debugDescription: "An offline search result must have HERE offline-local provenance."
            )
        }
        try self.init(
            id: container.decode(String.self, forKey: .id),
            title: container.decode(String.self, forKey: .title),
            address: container.decodeIfPresent(String.self, forKey: .address),
            coordinate: container.decode(OfflineGeoCoordinate.self, forKey: .coordinate),
            categories: container.decode([String].self, forKey: .categories),
            regionID: container.decode(OfflineMapRegionID.self, forKey: .regionID)
        )
    }
}

struct OfflineSearchResponse: Sendable {
    let results: [OfflineSearchResult]
    let coverage: OfflineInstalledCoverageEvidence
    let searchedAt: Date

    var coveredByRegionIDs: [OfflineMapRegionID] { coverage.regionIDs }

    init(
        results: [OfflineSearchResult],
        coverage: OfflineInstalledCoverageEvidence,
        searchedAt: Date = Date()
    ) throws {
        let coveredIDs = Set(coverage.regionIDs)
        guard results.allSatisfy({ coveredIDs.contains($0.regionID) }) else {
            throw OfflineMapCoreError.invalidInput(
                "Every offline search result must be attributed to the verified search coverage."
            )
        }
        self.results = results
        self.coverage = coverage
        self.searchedAt = searchedAt
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
