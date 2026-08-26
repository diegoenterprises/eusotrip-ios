//
//  PricedRouteCommerceClient.swift
//  EusoTrip
//
//  Native boundary for the server-owned 0518 commercial route authority.
//
//  Important invariants:
//  - Clients submit identity and intent only. They never submit route miles,
//    route progress, rate arithmetic, platform-fee arithmetic, or payouts.
//  - Uploaded rate sheets remain immutable proposals until a human confirms
//    one exact draft hash. Confirmation still does not activate the policy.
//  - Asset availability is mode-native and binds an exact licensed live
//    observation. A truck posting is not silently reused for rail or vessel.
//  - Quotes are immutable readbacks bound to an exact canonical route plan,
//    committed availability allocation, policy versions, and evidence hash.
//

import Foundation

@MainActor
struct PricedRouteCommerceClient {
    static let shared = PricedRouteCommerceClient(api: .shared)

    enum Mode: String, Codable, CaseIterable, Hashable, Sendable {
        case truck = "TRUCK"
        case rail = "RAIL"
        case vessel = "VESSEL"

        var accessibilityLabel: String {
            switch self {
            case .truck: return "Truck"
            case .rail: return "Rail"
            case .vessel: return "Vessel"
            }
        }
    }

    enum SubjectType: String, Codable, Hashable, Sendable {
        case load
        case railShipment = "rail_shipment"
        case vesselShipment = "vessel_shipment"
        case vesselVoyage = "vessel_voyage"
    }

    struct Subject: Codable, Hashable, Sendable {
        let type: SubjectType
        let id: Int

        init(type: SubjectType, id: Int) throws {
            guard id > 0 else { throw ClientError.invalidIdentifier }
            self.type = type
            self.id = id
        }

        var mode: Mode {
            switch type {
            case .load: return .truck
            case .railShipment: return .rail
            case .vesselShipment, .vesselVoyage: return .vessel
            }
        }
    }

    // MARK: - Immutable priced-route readback

    struct PricingBlocker: Decodable, Hashable, Sendable, Identifiable {
        let code: String
        let message: String
        let recovery: String

        var id: String { code + ":" + message }
    }

    struct RouteAuthority: Decodable, Hashable, Sendable {
        let bindingId: String
        let bindingVersionId: String
        let bindingRevision: Int
        let bindingHashSha256: String
        let routePlanId: String
        let routePlanPublicId: String
        let routePlanVersionId: String
        let routePlanVersion: Int
        let planChecksumSha256: String
        let geometryChecksumSha256: String
        let distanceMeters: Int
        let graphVersionId: String
        let graphBindingHashSha256: String
    }

    struct AvailabilityAuthority: Decodable, Hashable, Sendable {
        let offerId: String
        let offerPublicId: String
        let offerVersionId: String
        let version: Int
        let assetType: String
        let assetIdentityKey: String
        let liveObservationId: String
        let availabilityHashSha256: String
        let allocationId: String
        let allocationPublicId: String
        let allocationVersionId: String
        let allocationVersion: Int
        let allocationState: String
        let allocationHashSha256: String
    }

    struct MovementLeg: Decodable, Hashable, Sendable, Identifiable {
        let sequence: Int
        let operationalMovementVersionId: String
        let movementRouteBindingId: String
        let routePlanId: String
        let routePlanSegmentId: String
        let routePlanVersionId: String
        let revenueClassification: String
        let movementKind: String
        let distanceMeters: Int
        let durationSeconds: Int?
        let classificationHashSha256: String

        var id: Int { sequence }
    }

    struct LineItem: Decodable, Hashable, Sendable, Identifiable {
        let sequence: Int
        let policyVersionId: String
        let movementLegSequence: Int?
        let code: String
        let category: String
        let direction: String
        let calculationKind: String
        let amountMinor: String
        let calculationHashSha256: String

        var id: Int { sequence }
    }

    struct Totals: Decodable, Hashable, Sendable {
        let serviceRevenueMinor: String
        let customerCreditsMinor: String
        let taxMinor: String
        let customerTotalMinor: String
        let platformFeeMinor: String
        let settlementPoolMinor: String
        let carrierPayoutMinor: String
        let driverPayoutMinor: String
        let catalystPayoutMinor: String
        let otherPayoutMinor: String
        let reconciliationMinor: String
    }

    struct Quote: Decodable, Hashable, Sendable, Identifiable {
        let schema: String
        let quoteId: String
        let quotePublicId: String
        let quoteVersionId: String
        let quoteVersionPublicId: String
        let version: Int
        let mode: Mode
        let subject: Subject
        let createdAt: String
        let evidenceHashSha256: String
        let pricingState: String
        let route: RouteAuthority?
        let availability: AvailabilityAuthority?
        let currency: String?
        let currencyScale: Int?
        let roundingMode: String?
        let movementLegs: [MovementLeg]
        let lineItems: [LineItem]
        let totals: Totals?
        let blockers: [PricingBlocker]

        var id: String { quoteVersionPublicId }
        var isExecutable: Bool {
            pricingState == "priced" && route != nil && availability != nil
                && totals != nil && blockers.isEmpty
        }
    }

    private struct PriceInput: Encodable {
        let subject: Subject
        let requestId: String
    }

    private struct ReadQuoteInput: Encodable {
        let subject: Subject
    }

    /// Creates a new immutable server price version from subject identity.
    /// The server resolves route, availability, policies, fees, and payouts.
    func price(subject: Subject, requestId: UUID = UUID()) async throws -> Quote {
        try await api.mutation(
            "pricedRoute.price",
            input: PriceInput(subject: subject, requestId: requestId.uuidString.lowercased())
        )
    }

    func currentQuote(subject: Subject) async throws -> Quote {
        try await api.query(
            "pricedRoute.getCurrent",
            input: ReadQuoteInput(subject: subject)
        )
    }

    // MARK: - Immutable rate-sheet proposal and confirmation

    enum RateSheetMediaType: String, Codable, Hashable, Sendable {
        case pdf = "application/pdf"
        case png = "image/png"
        case jpeg = "image/jpeg"
        case webp = "image/webp"
        case csv = "text/csv"
        case plainText = "text/plain"
        case xls = "application/vnd.ms-excel"
        case xlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case doc = "application/msword"
        case docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    }

    struct RateSheetBlocker: Decodable, Hashable, Sendable, Identifiable {
        let code: String
        let path: String
        let message: String
        let recovery: String
        let evidenceRefs: [String]

        var id: String { code + ":" + path }
    }

    struct ParserEvidence: Decodable, Hashable, Sendable {
        let parserId: String
        let parserVersion: String
        let providerId: String
        let modelId: String?
        let modelVersion: String?
        let grounded: Bool
        let warnings: [String]
    }

    struct CanonicalPolicyTerms: Decodable, Hashable, Sendable {
        let schema: String
        let currency: String
        let currencyScale: Int
        let roundingMode: String
    }

    struct RateSheetProposal: Decodable, Hashable, Sendable {
        let schema: String
        let mode: Mode
        let policyKind: String
        let sourceDocumentPublicId: String
        let sourceDocumentHashSha256: String
        let canonicalPolicyTerms: CanonicalPolicyTerms?
        let parser: ParserEvidence
        let validationBlockers: [RateSheetBlocker]
        let extractionState: String
        let activationState: String

        var canConfirm: Bool {
            canonicalPolicyTerms != nil && validationBlockers.isEmpty
        }
    }

    struct SourceDocument: Decodable, Hashable, Sendable {
        let sourceDocumentId: String
        let sourceDocumentPublicId: String
        let documentId: Int?
        let storageReference: String
        let originalFileName: String
        let mediaType: RateSheetMediaType
        let byteLength: Int
        let pageCount: Int?
        let originalFileHashSha256: String
        let receivedAt: String
    }

    struct RateSheetDraft: Decodable, Hashable, Sendable, Identifiable {
        let draftId: String
        let draftPublicId: String
        let draftHashSha256: String
        let state: String
        let effectiveState: String
        let createdAt: String
        let proposal: RateSheetProposal
        let sourceDocument: SourceDocument

        var id: String { draftPublicId }
        var canConfirm: Bool {
            effectiveState == "proposal" && proposal.canConfirm
        }
    }

    struct RateSheetConfirmation: Decodable, Hashable, Sendable {
        let confirmationId: String
        let confirmationPublicId: String
        let draftId: String
        let draftPublicId: String
        let confirmedRulesHashSha256: String
        let confirmationStatement: String
        let confirmationStatementHashSha256: String
        let confirmedByUserId: Int
        let confirmedAt: String
        let activationState: String
        let canonicalPolicyTerms: CanonicalPolicyTerms
    }

    struct RateSheetDetail: Decodable, Hashable, Sendable {
        let draft: RateSheetDraft
        let confirmation: RateSheetConfirmation?
    }

    struct RateSheetIngestResult: Decodable, Hashable, Sendable {
        let sourceDocument: SourceDocument
        let drafts: [RateSheetDraft]
        let automaticallyActivated: Bool
    }

    private struct IngestRateSheetInput: Encodable {
        let mode: Mode
        let fileBase64: String
        let fileName: String
        let mediaType: RateSheetMediaType
        let documentId: Int?
        let requestKey: String
    }

    private struct ListRateSheetsInput: Encodable {
        let mode: Mode?
        let effectiveState: String?
        let limit: Int
    }

    private struct GetRateSheetInput: Encodable {
        let draftPublicId: String
    }

    private struct ConfirmRateSheetInput: Encodable {
        let draftPublicId: String
        let expectedDraftHashSha256: String
        let confirmationStatement: String
        let requestKey: String
    }

    func ingestRateSheet(
        mode: Mode,
        data: Data,
        fileName: String,
        mediaType: RateSheetMediaType,
        documentId: Int? = nil,
        requestKey: UUID = UUID()
    ) async throws -> RateSheetIngestResult {
        let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !data.isEmpty, !trimmedName.isEmpty else {
            throw ClientError.emptyRateSheetArtifact
        }
        return try await api.mutation(
            "pricedRouteRateSheet.ingest",
            input: IngestRateSheetInput(
                mode: mode,
                fileBase64: data.base64EncodedString(),
                fileName: trimmedName,
                mediaType: mediaType,
                documentId: documentId,
                requestKey: requestKey.uuidString.lowercased()
            )
        )
    }

    func listRateSheets(
        mode: Mode? = nil,
        effectiveState: String? = nil,
        limit: Int = 50
    ) async throws -> [RateSheetDraft] {
        guard (1...100).contains(limit) else { throw ClientError.invalidLimit }
        return try await api.query(
            "pricedRouteRateSheet.list",
            input: ListRateSheetsInput(
                mode: mode,
                effectiveState: effectiveState,
                limit: limit
            )
        )
    }

    func rateSheet(draftPublicId: UUID) async throws -> RateSheetDetail {
        try await api.query(
            "pricedRouteRateSheet.get",
            input: GetRateSheetInput(draftPublicId: draftPublicId.uuidString.lowercased())
        )
    }

    func confirmRateSheet(
        draft: RateSheetDraft,
        statement: String,
        requestKey: UUID = UUID()
    ) async throws -> RateSheetConfirmation {
        guard draft.canConfirm else { throw ClientError.rateSheetHasBlockers }
        let reviewed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard reviewed.count >= 20 else { throw ClientError.confirmationTooShort }
        return try await api.mutation(
            "pricedRouteRateSheet.confirm",
            input: ConfirmRateSheetInput(
                draftPublicId: draft.draftPublicId,
                expectedDraftHashSha256: draft.draftHashSha256,
                confirmationStatement: reviewed,
                requestKey: requestKey.uuidString.lowercased()
            )
        )
    }

    // MARK: - Mode-native asset availability

    enum Asset: Hashable, Sendable, Encodable {
        case truckVehicle(Int)
        case railConsist(Int)
        case railcar(Int)
        case vessel(Int)

        var mode: Mode {
            switch self {
            case .truckVehicle: return .truck
            case .railConsist, .railcar: return .rail
            case .vessel: return .vessel
            }
        }

        var identityKey: String {
            switch self {
            case .truckVehicle(let id): return "truck_vehicle:\(id)"
            case .railConsist(let id): return "rail_consist:\(id)"
            case .railcar(let id): return "railcar:\(id)"
            case .vessel(let id): return "vessel:\(id)"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case assetType, vehicleId, trainConsistId, railcarId, vesselId
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .truckVehicle(let id):
                guard id > 0 else { throw ClientError.invalidIdentifier }
                try container.encode("truck_vehicle", forKey: .assetType)
                try container.encode(id, forKey: .vehicleId)
            case .railConsist(let id):
                guard id > 0 else { throw ClientError.invalidIdentifier }
                try container.encode("rail_consist", forKey: .assetType)
                try container.encode(id, forKey: .trainConsistId)
            case .railcar(let id):
                guard id > 0 else { throw ClientError.invalidIdentifier }
                try container.encode("railcar", forKey: .assetType)
                try container.encode(id, forKey: .railcarId)
            case .vessel(let id):
                guard id > 0 else { throw ClientError.invalidIdentifier }
                try container.encode("vessel", forKey: .assetType)
                try container.encode(id, forKey: .vesselId)
            }
        }
    }

    enum Responsibility: String, Codable, CaseIterable, Hashable, Sendable {
        case carrier, shipper
        case sharedByContract = "shared_by_contract"
    }

    struct TruckAvailabilityTerms: Encodable, Hashable, Sendable {
        let schema = "truck-availability.v1"
        let equipmentTypes: [String]
        let availablePayloadKg: Int
        let serviceRadiusMeters: Int
        let maxDeadheadMeters: Int
        let operatingRegions: [String]
        let restrictions: [String]
        let deadheadResponsibility: Responsibility
    }

    struct RailAvailabilityTerms: Encodable, Hashable, Sendable {
        enum AssetKind: String, Encodable, Hashable, Sendable {
            case railConsist = "rail_consist"
            case railcar
        }

        let schema = "rail-availability.v1"
        let assetKind: AssetKind
        let availableCapacityKg: Int?
        let availableVolumeCubicMeters: Double?
        let interchangePoints: [String]
        let commodityRestrictions: [String]
        let clearanceRestrictions: [String]
        let positioningResponsibility: Responsibility
        let emptyReturnResponsibility: Responsibility
    }

    struct VesselAvailabilityTerms: Encodable, Hashable, Sendable {
        enum CharterResponsibility: String, Encodable, CaseIterable, Hashable, Sendable {
            case owner, charterer
            case sharedByContract = "shared_by_contract"
        }

        enum PortApproachResponsibility: String, Encodable, CaseIterable, Hashable, Sendable {
            case owner, charterer
            case passThrough = "pass_through"
        }

        let schema = "vessel-availability.v1"
        let laycanStart: String
        let laycanEnd: String
        let portRangeUnlocodes: [String]
        let maximumDraughtMillimeters: Int
        let availableDeadweightTonnage: Int
        let cargoRestrictions: [String]
        let ballastResponsibility: CharterResponsibility
        let portApproachResponsibility: PortApproachResponsibility
    }

    enum AvailabilityTerms: Encodable, Hashable, Sendable {
        case truck(TruckAvailabilityTerms)
        case rail(RailAvailabilityTerms)
        case vessel(VesselAvailabilityTerms)

        var mode: Mode {
            switch self {
            case .truck: return .truck
            case .rail: return .rail
            case .vessel: return .vessel
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .truck(let value): try value.encode(to: encoder)
            case .rail(let value): try value.encode(to: encoder)
            case .vessel(let value): try value.encode(to: encoder)
            }
        }
    }

    struct Allocation: Decodable, Hashable, Sendable, Identifiable {
        let id: String
        let publicId: String
        let versionId: String
        let versionPublicId: String
        let version: Int
        let state: String
        let offerId: String
        let offerVersionId: String
        let ownerCompanyId: Int
        let requesterCompanyId: Int
        let mode: Mode
        let subject: Subject
        let reservationExpiresAt: String?
        let allocationTermsHashSha256: String
        let allocationHashSha256: String
        let createdAt: String
    }

    struct AvailabilityOffer: Decodable, Hashable, Sendable, Identifiable {
        struct AssetIdentity: Decodable, Hashable, Sendable {
            let assetType: String
            let vehicleId: Int?
            let trainConsistId: Int?
            let railcarId: Int?
            let vesselId: Int?
        }

        let schema: String
        let offerId: String
        let offerPublicId: String
        let offerVersionId: String
        let offerVersionPublicId: String
        let version: Int
        let ownerCompanyId: Int
        let mode: Mode
        let asset: AssetIdentity
        let assetIdentityKey: String
        let availabilityProfileVersionId: String
        let routeAssetProfileVersionId: String?
        let liveObservationId: String
        let observedAt: String
        let state: String
        let freshness: String
        let availableFrom: String
        let availableUntil: String
        let maxPositionAgeSeconds: Int
        let availabilityHashSha256: String
        let currentAllocation: Allocation?

        var id: String { offerPublicId }
        var isActionable: Bool {
            state == "available" && freshness == "current" && currentAllocation == nil
        }
    }

    struct AvailabilityPrerequisiteBlocker: Decodable, Hashable, Sendable, Identifiable {
        let code: String
        let message: String
        let recovery: String

        var id: String { code + ":" + message }
    }

    struct AvailabilityObservationPrerequisite: Decodable, Hashable, Sendable {
        let liveObservationId: String?
        let observedAt: String
        let receivedAt: String
        let ageSeconds: Int
        let maximumPermittedAgeSeconds: Int
        let freshness: String
        let qualityState: String
        let providerId: String
        let providerSourceVersion: String
        let sourceClass: String
        let providerLimitClass: String
        let limitationsStatement: String
        let licenseAgreementId: String
        let licenseName: String
        let licenseVersion: String
        let evidenceHashSha256: String
        let provenanceHashSha256: String
    }

    struct AvailabilityPublishPrerequisite: Decodable, Hashable, Sendable, Identifiable {
        struct AssetIdentity: Decodable, Hashable, Sendable {
            let assetType: String
            let vehicleId: Int?
            let trainConsistId: Int?
            let railcarId: Int?
            let vesselId: Int?

            var asset: Asset? {
                switch assetType {
                case "truck_vehicle":
                    return vehicleId.map(Asset.truckVehicle)
                case "rail_consist":
                    return trainConsistId.map(Asset.railConsist)
                case "railcar":
                    return railcarId.map(Asset.railcar)
                case "vessel":
                    return vesselId.map(Asset.vessel)
                default:
                    return nil
                }
            }
        }

        let schema: String
        let mode: Mode
        let asset: AssetIdentity
        let assetIdentityKey: String
        let displayName: String
        let detail: String
        let operationalState: String
        let routeAssetProfileVersionId: String?
        let routeAssetProfileValidUntil: String?
        let routeAssetProfileSnapshotHashSha256: String?
        let observation: AvailabilityObservationPrerequisite?
        let blockers: [AvailabilityPrerequisiteBlocker]
        let readyToPublish: Bool

        var id: String { assetIdentityKey }

        func routeProfileVersionID(covering availableUntil: Date) -> String? {
            guard let routeAssetProfileVersionId else { return nil }
            guard let routeAssetProfileValidUntil,
                  let expiry = Self.date(from: routeAssetProfileValidUntil) else {
                return routeAssetProfileVersionId
            }
            return expiry >= availableUntil ? routeAssetProfileVersionId : nil
        }

        private static func date(from value: String) -> Date? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            return fallback.date(from: value)
        }
    }

    struct AvailabilityPublishPrerequisiteList: Decodable, Hashable, Sendable {
        let schema: String
        let mode: Mode
        let asOf: String
        let assets: [AvailabilityPublishPrerequisite]
    }

    private struct PublishAvailabilityInput: Encodable {
        let asset: Asset
        let routeAssetProfileVersionId: String?
        let liveObservationId: String
        let state: String
        let availableFrom: String
        let availableUntil: String
        let maxPositionAgeSeconds: Int
        let terms: AvailabilityTerms
        let requestId: String
    }

    private struct AvailabilityListInput: Encodable {
        let mode: Mode?
        let state: String?
        let limit: Int
        let cursor: String?
    }

    private struct AvailabilityPrerequisiteListInput: Encodable {
        let mode: Mode
        let limit: Int
    }

    private struct WithdrawAvailabilityInput: Encodable {
        let offerId: String
        let expectedVersion: Int
        let reason: String
        let requestId: String
    }

    func publishAvailability(
        asset: Asset,
        routeAssetProfileVersionId: String?,
        liveObservationId: String,
        availableFrom: Date,
        availableUntil: Date,
        maxPositionAgeSeconds: Int,
        terms: AvailabilityTerms,
        requestId: UUID = UUID()
    ) async throws -> AvailabilityOffer {
        guard asset.mode == terms.mode else { throw ClientError.modeMismatch }
        guard availableUntil > availableFrom else { throw ClientError.invalidAvailabilityWindow }
        guard (1...86_400).contains(maxPositionAgeSeconds) else {
            throw ClientError.invalidFreshnessWindow
        }
        guard Self.isUnsignedIdentifier(liveObservationId),
              routeAssetProfileVersionId.map(Self.isUnsignedIdentifier) ?? true else {
            throw ClientError.invalidIdentifier
        }
        return try await api.mutation(
            "modeAssetAvailability.publish",
            input: PublishAvailabilityInput(
                asset: asset,
                routeAssetProfileVersionId: routeAssetProfileVersionId,
                liveObservationId: liveObservationId,
                state: availableFrom > Date() ? "scheduled" : "available",
                availableFrom: Self.iso8601.string(from: availableFrom),
                availableUntil: Self.iso8601.string(from: availableUntil),
                maxPositionAgeSeconds: maxPositionAgeSeconds,
                terms: terms,
                requestId: requestId.uuidString.lowercased()
            )
        )
    }

    func listAvailability(
        mode: Mode? = nil,
        state: String? = nil,
        limit: Int = 50,
        cursor: String? = nil
    ) async throws -> [AvailabilityOffer] {
        guard (1...100).contains(limit) else { throw ClientError.invalidLimit }
        guard cursor.map(Self.isUnsignedIdentifier) ?? true else {
            throw ClientError.invalidIdentifier
        }
        return try await api.query(
            "modeAssetAvailability.listMine",
            input: AvailabilityListInput(mode: mode, state: state, limit: limit, cursor: cursor)
        )
    }

    func listAvailabilityPublishPrerequisites(
        mode: Mode,
        limit: Int = 100
    ) async throws -> AvailabilityPublishPrerequisiteList {
        guard (1...100).contains(limit) else { throw ClientError.invalidLimit }
        return try await api.query(
            "modeAssetAvailability.listPublishPrerequisites",
            input: AvailabilityPrerequisiteListInput(mode: mode, limit: limit)
        )
    }

    func withdrawAvailability(
        _ offer: AvailabilityOffer,
        reason: String,
        requestId: UUID = UUID()
    ) async throws -> AvailabilityOffer {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClientError.withdrawalReasonRequired }
        return try await api.mutation(
            "modeAssetAvailability.withdraw",
            input: WithdrawAvailabilityInput(
                offerId: offer.offerId,
                expectedVersion: offer.version,
                reason: trimmed,
                requestId: requestId.uuidString.lowercased()
            )
        )
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func isUnsignedIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy(\.isNumber)
            && (value == "0" || value.first != "0")
    }

    private let api: EusoTripAPI

    init(api: EusoTripAPI) {
        self.api = api
    }
}

extension PricedRouteCommerceClient {
    enum ClientError: LocalizedError {
        case invalidIdentifier
        case invalidLimit
        case emptyRateSheetArtifact
        case rateSheetHasBlockers
        case confirmationTooShort
        case modeMismatch
        case invalidAvailabilityWindow
        case invalidFreshnessWindow
        case withdrawalReasonRequired

        var errorDescription: String? {
            switch self {
            case .invalidIdentifier:
                return "This record is not linked to a valid load, shipment, or offer."
            case .invalidLimit:
                return "The requested result limit is outside the supported range."
            case .emptyRateSheetArtifact:
                return "Choose a non-empty rate-sheet document."
            case .rateSheetHasBlockers:
                return "Review and clear every extraction blocker before confirming this proposal."
            case .confirmationTooShort:
                return "Record a specific review statement of at least 20 characters."
            case .modeMismatch:
                return "The availability terms do not belong to this asset's transport mode."
            case .invalidAvailabilityWindow:
                return "Availability must end after it begins."
            case .invalidFreshnessWindow:
                return "The live-position freshness window must be between one second and 24 hours."
            case .withdrawalReasonRequired:
                return "Record why this capacity is no longer available."
            }
        }
    }
}
