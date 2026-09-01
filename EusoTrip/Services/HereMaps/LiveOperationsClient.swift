//
//  LiveOperationsClient.swift
//  EusoTrip
//
//  Typed native client for the server-owned Live Operations authority.
//  Selected assets resolve through tenant grants, provider licence, consent,
//  and immutable observation evidence. This client never calls a provider
//  directly and never authors route geometry or progress.
//

import Foundation

struct LiveOperationsClient {
    static let shared = LiveOperationsClient(api: .shared)

    enum Mode: String, Decodable, Hashable, Sendable {
        case truck = "TRUCK"
        case rail = "RAIL"
        case vessel = "VESSEL"
    }

    enum Freshness: String, Decodable, Hashable, Sendable {
        case live, delayed, stale, offline
    }

    enum QualityState: String, Decodable, Hashable, Sendable {
        case verified
        case providerReported = "provider_reported"
        case conflicted
        case rejected
    }

    struct Reference: Codable, Hashable, Sendable {
        let kind: String
        let value: String
    }

    struct Asset: Decodable, Hashable, Sendable {
        let sourcePublicId: String
        let identityKey: String
        let accessBasis: String
    }

    struct Provider: Decodable, Hashable, Sendable {
        let id: String
        let sourceId: String
        let sourceVersion: String
        let integrationObservationId: String?
        let limitClass: String
        let limitationsStatement: String
        let coverageState: String
    }

    struct Position: Decodable, Hashable, Sendable {
        let latitude: Double
        let longitude: Double
        let accuracyMeters: Double?
        let courseDegrees: Double?
        let speedMetersPerSecond: Double?

        var coordinate: HereLatLng? {
            guard let coordinate = LatLongParser.validatedCoordinate(
                latitude: latitude,
                longitude: longitude
            ) else { return nil }
            return HereLatLng(coordinate)
        }
    }

    struct QualityEvidence: Decodable, Hashable, Sendable {
        let carrierScac: String?
        let nextCarrierScac: String?
        let eventDescription: String?
        let nextScheduledEventDescription: String?
        let shipmentExceptionDescription: String?
        let equipmentLoadStatusCode: String?
        let originLocation: String?
        let destinationLocation: String?
        let finalDestinationLocation: String?
        let estimatedAvailabilityDate: String?
        let estimatedAvailabilityTime: String?
        let trainId: String?
        let providerConfidence: Double?
        let continuityClaimed: Bool?
        let trackOccupancyClaimed: Bool?
        let aisTimestamp: String?
        let receptionCoverageClaimed: Bool?
    }

    struct Quality: Decodable, Hashable, Sendable {
        let state: QualityState
        let evidence: QualityEvidence
        let evidenceHashSha256: String
    }

    struct Licence: Decodable, Hashable, Sendable {
        let agreementId: String
        let termsHashSha256: String
    }

    struct Projection: Decodable, Hashable, Sendable {
        let publicId: String
        let basis: String
        let state: String
        let graphVersionId: String?
        let graphNodeId: String?
        let graphEdgeId: String?
        let routePlanVersionId: String?
        let routePlanSegmentId: String?
        let projectedLatitude: Double?
        let projectedLongitude: Double?
        let offsetMeters: Double?
        let engineId: String
        let engineVersion: String
        let checksumSha256: String
        let projectedAt: String
    }

    struct Observation: Decodable, Hashable, Sendable {
        let publicId: String
        let mode: Mode
        let asset: Asset
        let provider: Provider
        let position: Position
        let observedAt: String
        let receivedAt: String
        let freshnessState: Freshness
        let quality: Quality
        let provenanceHashSha256: String
        let evidenceHashSha256: String
        let license: Licence
        /// Present only on a tenant-authorized nearby query. Asset-specific
        /// reads intentionally omit it.
        let distanceMeters: Double?
        let operationalUseAllowed: Bool
        let projection: Projection?

        var markerState: HereObservationState {
            guard operationalUseAllowed else { return .degraded }
            if quality.state == .conflicted || quality.state == .rejected {
                return .degraded
            }
            switch freshnessState {
            case .live:
                return quality.state == .verified ? .current : .degraded
            case .delayed:
                return .degraded
            case .stale:
                return .stale
            case .offline:
                return .offline
            }
        }

        var accessibleEvidenceLabel: String {
            let operational = operationalUseAllowed
                ? "operational use allowed"
                : "operational use not established"
            return [
                "provider \(provider.id)",
                "source \(provider.sourceId) version \(provider.sourceVersion)",
                "observed \(observedAt)",
                "received \(receivedAt)",
                "freshness \(freshnessState.rawValue)",
                "quality \(quality.state.rawValue)",
                operational,
                provider.limitationsStatement,
            ].joined(separator: ", ")
        }
    }

    struct Coverage: Decodable, Hashable, Sendable {
        let areaCoverageClaimed: Bool
        let state: String
        let statement: String
    }

    struct AssetResult: Decodable, Hashable, Sendable {
        let mode: Mode
        let asOf: String
        let reference: Reference
        let observation: Observation?
        let coverage: Coverage
        let modeLimitation: String
    }

    struct NearbyCenter: Decodable, Hashable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    struct NearbyResult: Decodable, Hashable, Sendable {
        let mode: Mode
        let asOf: String
        let center: NearbyCenter
        let radiusMeters: Int
        let observations: [Observation]
        let coverage: Coverage
        let modeLimitation: String

        /// The server can expose licensed evidence that is not cleared for
        /// operational use. It remains available for an honest status panel,
        /// but it must not become an actionable map puck.
        var operationalObservations: [Observation] {
            observations.filter(\.operationalUseAllowed)
        }
    }

    private struct LatestInput: Encodable {
        let mode: String
        let reference: Reference
    }

    private struct NearbyInput: Encodable {
        struct Center: Encodable {
            let latitude: Double
            let longitude: Double
        }

        let mode: String
        let center: Center
        let radiusMeters: Int
        let limit: Int
    }

    private let api: EusoTripAPI

    init(api: EusoTripAPI) {
        self.api = api
    }

    func latestTruck(vehicleId: Int) async throws -> AssetResult {
        try await latest(
            mode: .truck,
            reference: .init(kind: "truck_vehicle_id", value: String(vehicleId))
        )
    }

    func latestRailcar(number: String) async throws -> AssetResult {
        try await latest(
            mode: .rail,
            reference: .init(
                kind: "railcar_number",
                value: number.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            )
        )
    }

    func latestVessel(imoNumber: String) async throws -> AssetResult {
        try await latest(
            mode: .vessel,
            reference: .init(
                kind: "vessel_imo",
                value: imoNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    func latestVessel(mmsiNumber: String) async throws -> AssetResult {
        try await latest(
            mode: .vessel,
            reference: .init(
                kind: "vessel_mmsi",
                value: mmsiNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    /// Returns only exact, tenant-authorized observations around a real
    /// center. An empty result never claims that the provider covers the area.
    func nearby(
        mode: Mode,
        center: HereLatLng,
        radiusMeters: Int,
        limit: Int = 100
    ) async throws -> NearbyResult {
        guard center.isUsableCoordinate else {
            throw LiveOperationsClientError.invalidCenter
        }
        guard (1...200_000).contains(radiusMeters) else {
            throw LiveOperationsClientError.invalidRadius
        }
        guard (1...250).contains(limit) else {
            throw LiveOperationsClientError.invalidLimit
        }

        return try await api.query(
            "liveOperations.nearby",
            input: NearbyInput(
                mode: mode.rawValue,
                center: .init(latitude: center.lat, longitude: center.lng),
                radiusMeters: radiusMeters,
                limit: limit
            )
        )
    }

    private func latest(mode: Mode, reference: Reference) async throws -> AssetResult {
        try await api.query(
            "liveOperations.latestForAsset",
            input: LatestInput(mode: mode.rawValue, reference: reference)
        )
    }
}

private enum LiveOperationsClientError: LocalizedError {
    case invalidCenter
    case invalidRadius
    case invalidLimit

    var errorDescription: String? {
        switch self {
        case .invalidCenter:
            return "A valid map center is required for nearby Live Operations."
        case .invalidRadius:
            return "Nearby Live Operations radius must be between 1 and 200,000 meters."
        case .invalidLimit:
            return "Nearby Live Operations limit must be between 1 and 250 observations."
        }
    }
}
