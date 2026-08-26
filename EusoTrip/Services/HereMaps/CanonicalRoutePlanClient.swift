//
//  CanonicalRoutePlanClient.swift
//  EusoTrip
//
//  Read-only native contract for the server-owned route.plan authority.
//  The client may identify a freight subject and purpose, but it never sends
//  endpoints, mode, tenant, equipment/profile facts, source evidence, or
//  geometry. Only an exact persisted operational binding may reach a renderer.
//

import Foundation

@MainActor
struct CanonicalRoutePlanClient {
    static let shared = CanonicalRoutePlanClient(api: .shared)

    private static let maximumSafeJSONInteger = 9_007_199_254_740_991

    enum Subject: Equatable, Sendable {
        case load(Int)
        case railShipment(Int)
        case vesselShipment(Int)
        case vesselVoyage(Int)

        fileprivate var wireType: String {
            switch self {
            case .load: return "load"
            case .railShipment: return "rail_shipment"
            case .vesselShipment: return "vessel_shipment"
            case .vesselVoyage: return "vessel_voyage"
            }
        }

        fileprivate var id: Int {
            switch self {
            case .load(let id),
                 .railShipment(let id),
                 .vesselShipment(let id),
                 .vesselVoyage(let id):
                return id
            }
        }
    }

    enum Purpose: String, Codable, CaseIterable, Sendable {
        case posting
        case planning
        case activeJob = "active_job"
        case reroute
    }

    enum Mode: String, Decodable, Sendable {
        case truck = "TRUCK"
        case rail = "RAIL"
        case vessel = "VESSEL"
    }

    enum ExecutionEvidenceState: String, Decodable, Sendable {
        case unobserved
        case current
        case stale
        case offRoute = "off_route"
        case arrived
    }

    enum ExecutionProjectionStatus: String, Decodable, Sendable {
        case onRoute = "on_route"
        case offRoute = "off_route"
        case stale
        case unknown
        case arrived
    }

    enum ExecutionFreshnessState: String, Decodable, Sendable {
        case current
        case stale
        case expired
        case unknown
    }

    enum ExecutionQualityState: String, Decodable, Sendable {
        case verified
        case reported
        case conflicted
        case rejected
    }

    enum ExecutionSourceType: String, Decodable, Sendable {
        case deviceGNSS = "device_gnss"
        case eld
        case railProvider = "rail_provider"
        case waysideDetector = "wayside_detector"
        case ais
        case portTerminal = "port_terminal"
        case operatorAttested = "operator_attested"
    }

    enum ExecutionAssetType: String, Decodable, Sendable {
        case vehicle
        case train
        case vessel
        case voyage
    }

    enum VersionState: String, Decodable, Sendable {
        case routePending = "route_pending"
        case ready
        case conditional
        case blocked
        case failed
        case insufficientEvidence = "insufficient_evidence"
    }

    enum RightsState: String, Decodable, Sendable {
        case valid
        case missing
        case expired
        case prohibited
        case revoked
        case unknown
    }

    enum FreshnessState: String, Decodable, Sendable {
        case current
        case stale
        case expired
        case unknown
    }

    enum SourceRole: String, Decodable, Sendable {
        case routeEngine = "route_engine"
        case graph
        case constraint
        case regulatory
        case trafficWeather = "traffic_weather"
        case validation
    }

    enum SourceSnapshotRole: String, Decodable, Sendable {
        case foundationGraph = "foundation_graph"
        case operationalConstraint = "operational_constraint"
        case regulatory
        case trafficWeather = "traffic_weather"
        case observation
        case displayOnly = "display_only"
    }

    enum SourceQualityState: String, Decodable, Sendable {
        case verified
        case reported
        case conflicted
        case rejected
        case unknown
    }

    enum SourceRevocationState: String, Decodable, Sendable {
        case active
        case revoked
        case superseded
    }

    enum WaypointKind: String, Decodable, Sendable {
        case origin
        case via
        case destination
        case pickup
        case delivery
        case railYard = "rail_yard"
        case interchange
        case port
        case pilotStation = "pilot_station"
        case anchorage
        case berth
    }

    enum ConstraintOutcome: String, Decodable, Sendable {
        case applied
        case cleared
        case warning
        case blocked
        case unknown
        case notApplicable = "not_applicable"
    }

    enum ProfilePurpose: String, Decodable, Sendable {
        case postingRequirement = "posting_requirement"
        case assignedAsset = "assigned_asset"
    }

    enum PersistenceOutcome: String, Decodable, Sendable {
        case succeeded
        case blocked
        case failed
    }

    enum BindingState: String, Decodable, Sendable {
        case active
        case pending
    }

    enum PendingReasonCode: String, Decodable, Sendable {
        case profileAuthorityRequired = "PROFILE_AUTHORITY_REQUIRED"
    }

    enum BlockerCode: String, Decodable, Sendable {
        case profileRequired = "PROFILE_REQUIRED"
        case profileVersionRequired = "PROFILE_VERSION_REQUIRED"
        case graphRequired = "GRAPH_REQUIRED"
        case ownedGraphRequired = "OWNED_GRAPH_REQUIRED"
        case graphNotReleased = "GRAPH_NOT_RELEASED"
        case graphNotCurrent = "GRAPH_NOT_CURRENT"
        case graphEvidenceUnbound = "GRAPH_EVIDENCE_UNBOUND"
        case requiredEvidenceMissing = "REQUIRED_EVIDENCE_MISSING"
        case sourceRightsInvalid = "SOURCE_RIGHTS_INVALID"
        case sourceNotCurrent = "SOURCE_NOT_CURRENT"
        case sourceNotAuthoritative = "SOURCE_NOT_AUTHORITATIVE"
        case waypointSemanticsInvalid = "WAYPOINT_SEMANTICS_INVALID"
        case modeSolverMismatch = "MODE_SOLVER_MISMATCH"
        case solverUnavailable = "SOLVER_UNAVAILABLE"
        case solverRejected = "SOLVER_REJECTED"
    }

    enum EvidenceKind: String, Decodable, Sendable {
        case truckRoadTopology = "truck.road_topology"
        case truckVehicleRestrictions = "truck.vehicle_restrictions"
        case truckRegulatoryAuthority = "truck.regulatory_authority"
        case truckValidation = "truck.validation"
        case railRouteEngine = "rail.route_engine"
        case railTopology = "rail.topology"
        case railClearance = "rail.clearance"
        case railCarrierAccess = "rail.carrier_access"
        case railOperatingPermission = "rail.operating_permission"
        case railValidation = "rail.validation"
        case vesselRouteEngine = "vessel.route_engine"
        case vesselOfficialChart = "vessel.official_chart"
        case vesselFairway = "vessel.fairway"
        case vesselDepth = "vessel.depth"
        case vesselRestriction = "vessel.restriction"
        case vesselCurrent = "vessel.current"
        case vesselValidation = "vessel.validation"
    }

    struct UnsignedBigIntID: RawRepresentable, Decodable, Equatable, Sendable {
        let rawValue: String

        init?(rawValue: String) {
            guard !rawValue.isEmpty,
                  rawValue.utf8.first != 48,
                  rawValue.utf8.allSatisfy({ 48...57 ~= $0 }),
                  UInt64(rawValue) != nil else { return nil }
            self.rawValue = rawValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected a positive canonical unsigned BIGINT string"
                )
            }
            self = value
        }
    }

    struct NonnegativeBigInt: RawRepresentable, Decodable, Equatable, Sendable {
        let rawValue: String

        init?(rawValue: String) {
            guard !rawValue.isEmpty,
                  rawValue.utf8.allSatisfy({ 48...57 ~= $0 }),
                  (rawValue == "0" || rawValue.utf8.first != 48),
                  UInt64(rawValue) != nil else { return nil }
            self.rawValue = rawValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected a canonical nonnegative unsigned BIGINT string"
                )
            }
            self = value
        }

        var uint64Value: UInt64 { UInt64(rawValue)! }
    }

    struct SHA256Digest: RawRepresentable, Decodable, Equatable, Sendable {
        let rawValue: String

        init?(rawValue: String) {
            guard rawValue.utf8.count == 64,
                  rawValue.utf8.allSatisfy({
                      (48...57 ~= $0) || (97...102 ~= $0)
                  }) else { return nil }
            self.rawValue = rawValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected a lowercase SHA-256 digest"
                )
            }
            self = value
        }
    }

    struct PublicUUID: RawRepresentable, Decodable, Equatable, Sendable {
        let rawValue: String

        init?(rawValue: String) {
            let bytes = Array(rawValue.utf8)
            let hyphenIndexes = Set([8, 13, 18, 23])
            guard bytes.count == 36,
                  bytes.enumerated().allSatisfy({ index, byte in
                      if hyphenIndexes.contains(index) { return byte == 45 }
                      return (48...57 ~= byte) || (97...102 ~= byte)
                  }),
                  49...53 ~= bytes[14],
                  [56, 57, 97, 98].contains(bytes[19]) else { return nil }
            self.rawValue = rawValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected a lowercase canonical UUID"
                )
            }
            self = value
        }
    }

    indirect enum JSONValue: Decodable, Equatable, Sendable {
        case null
        case bool(Bool)
        case integer(Int64)
        case number(Double)
        case string(String)
        case array([JSONValue])
        case object([String: JSONValue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self), value.isFinite {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSONValue].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: JSONValue].self) {
                self = .object(value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unsupported canonical JSON evidence value"
                )
            }
        }
    }

    struct Coordinate: Decodable, Equatable, Sendable {
        let lat: Double
        let lng: Double

        private enum CodingKeys: String, CodingKey { case lat, lng }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let lat = try container.decode(Double.self, forKey: .lat)
            let lng = try container.decode(Double.self, forKey: .lng)
            guard lat.isFinite, lng.isFinite,
                  (-90...90).contains(lat),
                  (-180...180).contains(lng) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .lat,
                    in: container,
                    debugDescription: "Coordinate is outside finite WGS-84 bounds"
                )
            }
            self.lat = lat
            self.lng = lng
        }
    }

    struct GeoJSONPosition: Decodable, Equatable, Sendable {
        let longitude: Double
        let latitude: Double

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let longitude = try container.decode(Double.self)
            let latitude = try container.decode(Double.self)
            guard container.isAtEnd,
                  longitude.isFinite,
                  latitude.isFinite,
                  (-180...180).contains(longitude),
                  (-90...90).contains(latitude) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "GeoJSON position must be exactly [longitude, latitude] in WGS-84 bounds"
                )
            }
            self.longitude = longitude
            self.latitude = latitude
        }

        fileprivate var rendererCoordinate: HereLatLng {
            HereLatLng(latitude, longitude)
        }
    }

    enum Geometry: Decodable, Equatable, Sendable {
        case lineString([GeoJSONPosition])
        case multiLineString([[GeoJSONPosition]])

        private enum CodingKeys: String, CodingKey { case type, coordinates }
        private enum GeometryType: String, Decodable {
            case lineString = "LineString"
            case multiLineString = "MultiLineString"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(GeometryType.self, forKey: .type) {
            case .lineString:
                let line = try container.decode([GeoJSONPosition].self, forKey: .coordinates)
                guard line.count >= 2 else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .coordinates,
                        in: container,
                        debugDescription: "LineString requires at least two positions"
                    )
                }
                self = .lineString(line)
            case .multiLineString:
                let lines = try container.decode([[GeoJSONPosition]].self, forKey: .coordinates)
                guard !lines.isEmpty, lines.allSatisfy({ $0.count >= 2 }) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .coordinates,
                        in: container,
                        debugDescription: "MultiLineString requires one or more independent two-position lines"
                    )
                }
                self = .multiLineString(lines)
            }
        }

        fileprivate var rendererLines: [[HereLatLng]] {
            switch self {
            case .lineString(let line):
                return [line.map(\.rendererCoordinate)]
            case .multiLineString(let lines):
                return lines.map { $0.map(\.rendererCoordinate) }
            }
        }
    }

    struct Identity: Decodable, Equatable, Sendable {
        let routePlanId: UnsignedBigIntID
        let routePlanPublicId: PublicUUID
        let routePlanVersionId: UnsignedBigIntID
        let version: Int
        let mode: Mode
        let planChecksum: SHA256Digest
        let geometryChecksum: SHA256Digest?
    }

    struct Engine: Decodable, Equatable, Sendable {
        let adapter: String
        let version: String
        let graphVersionId: UnsignedBigIntID?
    }

    struct Waypoint: Decodable, Equatable, Sendable {
        let sequence: Int
        let kind: WaypointKind
        let coordinate: Coordinate
        let label: String?
        let sourceEntityType: String?
        let sourceEntityId: UnsignedBigIntID?
        let identityHash: SHA256Digest
    }

    struct SourceProof: Decodable, Equatable, Sendable {
        let sourceSnapshotId: UnsignedBigIntID
        let sourcePublicId: PublicUUID
        let role: SourceRole
        let sourceRole: SourceSnapshotRole
        let authority: String
        let provider: String
        let dataset: String
        let recordId: String?
        let sourceVersion: String
        let adapterVersion: String
        let retrievedAt: String
        let effectiveAt: String?
        let expiresAt: String?
        let rightsState: RightsState
        let freshnessState: FreshnessState
        let qualityState: SourceQualityState
        let revocationState: SourceRevocationState
        let permitsOperationalUse: Bool
        let checksum: SHA256Digest
        let snapshotHash: SHA256Digest
        let attribution: String
    }

    struct Segment: Decodable, Equatable, Sendable {
        let sequence: Int
        let stableEdgeId: String
        let geometry: Geometry
        let geometryChecksum: SHA256Digest
        let distanceMeters: Int
        let durationSeconds: Int?
        let cumulativeStartMeters: Int
        let cumulativeEndMeters: Int
        let sourceSnapshotId: UnsignedBigIntID
        let logisticsEdgeId: Int?
        let fromNodeId: Int?
        let toNodeId: Int?
        let operatorRef: String?
        let semantics: [String: JSONValue]
        let constraints: [String: JSONValue]
    }

    struct Instruction: Decodable, Equatable, Sendable {
        let sequence: Int
        let segmentSequence: Int?
        let instructionType: String
        let title: String
        let visualText: String
        let spokenText: String
        let accessibilityText: String
        let triggerCoordinate: Coordinate?
        let triggerDistanceMeters: Int?
        let courseDegrees: Double?
        let semantics: [String: JSONValue]
    }

    struct Constraint: Decodable, Equatable, Sendable {
        let sequence: Int
        let segmentSequence: Int?
        let constraintType: String
        let outcome: ConstraintOutcome
        let requiredValue: String?
        let observedValue: String?
        let unit: String?
        let legalReference: String?
        let sourceSnapshotId: UnsignedBigIntID
        let evidence: [String: JSONValue]
    }

    struct Plan: Decodable, Equatable, Sendable {
        let identity: Identity
        let purpose: Purpose
        let state: VersionState
        let operational: Bool
        let operationalReason: String?
        let rightsState: RightsState
        let freshnessState: FreshnessState
        let modeGrammarVersion: String
        let engine: Engine
        let waypoints: [Waypoint]
        let geometry: Geometry?
        let distanceMeters: Int?
        let durationSeconds: Int?
        let sources: [SourceProof]
        let segments: [Segment]
        let instructions: [Instruction]
        let constraints: [Constraint]
        let warnings: [String]
        let createdAt: String
        let validFrom: String
        let validUntil: String?
    }

    struct ExecutionMember: Decodable, Equatable, Sendable {
        let id: UnsignedBigIntID
        let publicId: PublicUUID
        let replayed: Bool
    }

    struct ExecutionAssignmentResult: Decodable, Equatable, Sendable {
        let mode: Mode
        let assignment: ExecutionMember
    }

    struct ExecutionSynchronizationResult: Decodable, Equatable, Sendable {
        let synchronized: Bool
        let reason: String?
        let mode: Mode?
    }

    struct ExecutionAssignmentState: Decodable, Equatable, Sendable {
        let publicId: PublicUUID
        let routePlanVersionId: UnsignedBigIntID
        let assetType: ExecutionAssetType
        let assetRecordId: String
        let operatorUserId: Int
        let effectiveAt: String
        let expiresAt: String
        let totalDistanceMeters: NonnegativeBigInt
        let totalDurationSeconds: NonnegativeBigInt
    }

    struct ExecutionObservation: Decodable, Equatable, Sendable {
        let publicId: PublicUUID
        let sequence: Int
        let coordinate: Coordinate
        let observedAt: String
        let receivedAt: String
        let validUntil: String
        let freshnessState: ExecutionFreshnessState
        let qualityState: ExecutionQualityState
        let operationalUseAllowed: Bool
        let accuracyMeters: Double?
        let speedMetersPerSecond: Double?
        let courseDegrees: Double?
        let sourceType: ExecutionSourceType
        let provider: String
        let dataset: String
        let attribution: String
    }

    struct ExecutionProjection: Decodable, Equatable, Sendable {
        let publicId: PublicUUID
        let status: ExecutionProjectionStatus
        let projectedCoordinate: Coordinate?
        let distanceAlongMeters: NonnegativeBigInt?
        let remainingMeters: NonnegativeBigInt?
        let remainingSeconds: NonnegativeBigInt?
        let progressBasisPoints: Int?
        let eta: String?
        let confidence: Double?
        let currentForGuidance: Bool
    }

    struct ExecutionInstruction: Decodable, Equatable, Sendable {
        let id: UnsignedBigIntID
        let sequence: Int
        let instructionType: String
        let title: String
        let visualText: String
        let spokenText: String
        let accessibilityText: String
        let triggerCoordinate: Coordinate?
        let triggerDistanceMeters: NonnegativeBigInt?
        let courseDegrees: Double?
        let semantics: [String: JSONValue]
    }

    struct ExecutionGuidanceSnapshot: Equatable, Sendable {
        let mode: Mode
        let evidenceState: ExecutionEvidenceState
        let assignment: ExecutionAssignmentState
        let observation: ExecutionObservation
        let projection: ExecutionProjection
        let nextInstruction: ExecutionInstruction?
        let liveCoordinate: Coordinate
    }

    struct ExecutionState: Decodable, Equatable, Sendable {
        let mode: Mode
        let evidenceState: ExecutionEvidenceState
        let assignment: ExecutionAssignmentState
        let observation: ExecutionObservation?
        let projection: ExecutionProjection?
        let nextInstruction: ExecutionInstruction?

        /// Native guidance is released only from a current, operational,
        /// server-projected observation. A last-known coordinate may still be
        /// decoded for an explicitly stale UI, but it cannot drive the camera,
        /// progress, ETA, maneuver, or route reward state.
        var guidanceSnapshot: ExecutionGuidanceSnapshot? {
            guard evidenceState == .current || evidenceState == .arrived,
                  let observation,
                  observation.operationalUseAllowed,
                  observation.freshnessState == .current,
                  observation.qualityState == .verified ||
                    observation.qualityState == .reported,
                  let validUntil = CanonicalRoutePlanClient.parseInstant(
                    observation.validUntil
                  ),
                  validUntil > Date(),
                  let projection,
                  projection.currentForGuidance,
                  projection.status == .onRoute || projection.status == .arrived,
                  let liveCoordinate = projection.projectedCoordinate,
                  projection.progressBasisPoints.map({ (0...10_000).contains($0) }) ?? true,
                  projection.confidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                  observation.speedMetersPerSecond.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  observation.courseDegrees.map({ $0.isFinite && $0 >= 0 && $0 < 360 }) ?? true,
                  nextInstruction.map({ instruction in
                      !instruction.instructionType.isEmpty &&
                        !instruction.title.isEmpty &&
                        !instruction.visualText.isEmpty &&
                        !instruction.spokenText.isEmpty &&
                        !instruction.accessibilityText.isEmpty &&
                        (instruction.courseDegrees.map({ $0.isFinite && $0 >= 0 && $0 < 360 }) ?? true)
                  }) ?? true else { return nil }
            return ExecutionGuidanceSnapshot(
                mode: mode,
                evidenceState: evidenceState,
                assignment: assignment,
                observation: observation,
                projection: projection,
                nextInstruction: nextInstruction,
                liveCoordinate: liveCoordinate
            )
        }
    }

    struct RequestEvidence: Decodable, Equatable, Sendable {
        let requestId: UnsignedBigIntID
        let routePlanId: UnsignedBigIntID
        let requestKey: String
        let requestFingerprint: SHA256Digest
        let waypointManifestHashSha256: SHA256Digest
        let modeProfilePurpose: ProfilePurpose
        let modeSubjectProfileRegistrationId: UnsignedBigIntID
        let modeAssetProfileVersionId: UnsignedBigIntID?
        let modeProfileBindingHashSha256: SHA256Digest
        let requestVersion: Int
        let supersedesRequestId: UnsignedBigIntID?
        let state: PersistenceOutcome
        let auditOutboxId: UnsignedBigIntID
    }

    struct AttemptEvidence: Decodable, Equatable, Sendable {
        let attemptId: UnsignedBigIntID
        let requestId: UnsignedBigIntID
        let attemptNumber: Int
        let status: PersistenceOutcome
        let solverInputHashSha256: SHA256Digest
        let solverOutputHashSha256: SHA256Digest
        let graphVersionId: UnsignedBigIntID
        let modeProfileBindingHashSha256: SHA256Digest
        let graphBindingHashSha256: SHA256Digest
    }

    struct BindingIdentity: Decodable, Equatable, Sendable {
        let bindingId: UnsignedBigIntID
        let bindingPublicId: PublicUUID
        let bindingVersionId: UnsignedBigIntID
        let bindingRevision: Int
        let bindingHash: SHA256Digest
        let activePlanChecksum: SHA256Digest
        let state: BindingState
    }

    struct SourceBinding: Decodable, Equatable, Sendable {
        let proof: SourceProof
        let requiredForOperationalUse: Bool
    }

    struct BoundRoutePlan: Decodable, Equatable, Sendable {
        let plan: Plan
        let request: RequestEvidence
        let attempt: AttemptEvidence?
        let binding: BindingIdentity
        let sourceBindings: [SourceBinding]

        struct RendererSegment: Equatable, Sendable {
            let sequence: Int
            let stableEdgeId: String
            let geometryChecksum: SHA256Digest
            /// One entry per original GeoJSON line. Never flattened.
            let lines: [[HereLatLng]]
        }

        struct RendererPayload: Equatable, Sendable {
            let identity: Identity
            let binding: BindingIdentity
            /// One entry per original LineString/MultiLineString member.
            let lines: [[HereLatLng]]
            let segments: [RendererSegment]
        }

        /// Renderer-safe geometry exists only for the exact active,
        /// operational, checksum-bound plan. This method never repairs,
        /// interpolates, joins, snaps, or substitutes coordinates.
        var rendererPayload: RendererPayload? {
            guard plan.operational,
                  plan.state == .ready || plan.state == .conditional,
                  plan.operationalReason == nil,
                  plan.rightsState == .valid,
                  plan.freshnessState == .current,
                  plan.identity.geometryChecksum != nil,
                  let geometry = plan.geometry,
                  binding.state == .active,
                  binding.activePlanChecksum == plan.identity.planChecksum,
                  request.routePlanId == plan.identity.routePlanId,
                  let attempt,
                  attempt.requestId == request.requestId,
                  attempt.modeProfileBindingHashSha256 == request.modeProfileBindingHashSha256,
                  plan.engine.graphVersionId == attempt.graphVersionId,
                  !plan.sources.isEmpty,
                  sourceBindings.map(\.proof) == plan.sources,
                  profileBindingIsCoherent,
                  sequencesAreExact,
                  operationalContractIsCoherent else { return nil }

            let lines = geometry.rendererLines
            guard !lines.isEmpty, lines.allSatisfy({ $0.count >= 2 }) else { return nil }

            let rendererSegments = plan.segments.map { segment in
                RendererSegment(
                    sequence: segment.sequence,
                    stableEdgeId: segment.stableEdgeId,
                    geometryChecksum: segment.geometryChecksum,
                    lines: segment.geometry.rendererLines
                )
            }
            guard !rendererSegments.isEmpty,
                  rendererSegments.allSatisfy({
                      !$0.lines.isEmpty && $0.lines.allSatisfy({ $0.count >= 2 })
                  }) else { return nil }

            return RendererPayload(
                identity: plan.identity,
                binding: binding,
                lines: lines,
                segments: rendererSegments
            )
        }

        /// Convenience projection retaining every independent GeoJSON line.
        var rendererLines: [[HereLatLng]]? { rendererPayload?.lines }

        /// Convenience projection retaining every segment and every line
        /// inside that segment; discontinuities are never bridged.
        var rendererSegments: [RendererSegment]? { rendererPayload?.segments }

        private var profileBindingIsCoherent: Bool {
            guard request.requestVersion > 0,
                  request.state == .succeeded else { return false }
            switch request.modeProfilePurpose {
            case .postingRequirement:
                return plan.purpose == .posting && request.modeAssetProfileVersionId == nil
            case .assignedAsset:
                return plan.purpose != .posting && request.modeAssetProfileVersionId != nil
            }
        }

        private var sequencesAreExact: Bool {
            guard plan.waypoints.enumerated().allSatisfy({ $0.offset == $0.element.sequence }),
                  plan.segments.enumerated().allSatisfy({ $0.offset == $0.element.sequence }),
                  plan.instructions.enumerated().allSatisfy({ $0.offset == $0.element.sequence }),
                  plan.constraints.enumerated().allSatisfy({ $0.offset == $0.element.sequence }) else {
                return false
            }
            let segmentSequences = Set(plan.segments.map(\.sequence))
            return plan.instructions.allSatisfy({ instruction in
                instruction.segmentSequence.map(segmentSequences.contains) ?? true
            }) && plan.constraints.allSatisfy({ constraint in
                constraint.segmentSequence.map(segmentSequences.contains) ?? true
            })
        }

        /// Mirrors the server's operational release invariants at the native
        /// renderer boundary. Codable shape alone is not authority: a route
        /// that is internally contradictory, stale, incompletely sourced, or
        /// semantically wrong for its mode remains decodable for diagnostics
        /// but cannot release a line to HERE.
        private var operationalContractIsCoherent: Bool {
            guard plan.identity.version > 0,
                  binding.bindingRevision > 0,
                  request.requestVersion > 0,
                  let attempt,
                  attempt.attemptNumber > 0,
                  attempt.status == .succeeded,
                  plan.waypoints.count >= 2,
                  let distanceMeters = plan.distanceMeters,
                  distanceMeters > 0,
                  plan.durationSeconds.map({ $0 >= 0 }) ?? true,
                  !plan.segments.isEmpty,
                  canonicalText(plan.modeGrammarVersion),
                  canonicalText(plan.engine.adapter),
                  canonicalText(plan.engine.version),
                  canonicalText(request.requestKey),
                  routeValidityIsCurrent,
                  waypointSemanticsAreCoherent,
                  sourceEvidenceIsCoherent,
                  segmentEvidenceIsCoherent(expectedDistance: distanceMeters),
                  instructionEvidenceIsCoherent,
                  constraintEvidenceIsCoherent else { return false }
            return true
        }

        private var routeValidityIsCurrent: Bool {
            guard parseInstant(plan.createdAt) != nil,
                  let validFrom = parseInstant(plan.validFrom),
                  let validUntilRaw = plan.validUntil,
                  let validUntil = parseInstant(validUntilRaw),
                  validUntil > validFrom,
                  validUntil > Date() else { return false }
            return true
        }

        private var waypointSemanticsAreCoherent: Bool {
            guard let first = plan.waypoints.first,
                  let last = plan.waypoints.last,
                  first.identityHash != last.identityHash,
                  first.coordinate != last.coordinate,
                  plan.waypoints.allSatisfy({ waypoint in
                      waypoint.label.map(canonicalText) ?? true &&
                          waypoint.sourceEntityType.map(canonicalText) ?? true &&
                          ((waypoint.sourceEntityType == nil) ==
                              (waypoint.sourceEntityId == nil))
                  }) else { return false }

            let startKinds: [WaypointKind]
            let endKinds: [WaypointKind]
            switch plan.identity.mode {
            case .truck:
                startKinds = [.origin, .pickup]
                endKinds = [.destination, .delivery]
            case .rail:
                startKinds = [.origin, .pickup, .railYard]
                endKinds = [.destination, .delivery, .railYard]
            case .vessel:
                startKinds = [.origin, .port, .pilotStation, .anchorage, .berth]
                endKinds = [.destination, .port, .pilotStation, .anchorage, .berth]
            }
            return startKinds.contains(first.kind) && endKinds.contains(last.kind)
        }

        private var sourceEvidenceIsCoherent: Bool {
            let requiredRoles = requiredSourceRoles
            var identities = Set<String>()
            guard plan.sources.allSatisfy({ source in
                let identity = "\(source.sourceSnapshotId.rawValue):\(source.role.rawValue)"
                guard identities.insert(identity).inserted,
                      sourceRoleIsCompatible(source),
                      source.permitsOperationalUse,
                      source.rightsState == .valid,
                      source.freshnessState == .current,
                      source.revocationState == .active,
                      source.qualityState == .verified || source.qualityState == .reported,
                      source.sourceRole != .displayOnly,
                      canonicalText(source.authority),
                      canonicalText(source.provider),
                      canonicalText(source.dataset),
                      canonicalText(source.sourceVersion),
                      canonicalText(source.adapterVersion),
                      canonicalText(source.attribution),
                      source.recordId.map(canonicalText) ?? true,
                      sourceWindowCoversPlan(source) else { return false }
                return true
            }) else { return false }

            return requiredRoles.allSatisfy({ requiredRole in
                plan.sources.contains(where: { $0.role == requiredRole }) &&
                    sourceBindings.contains(where: {
                        $0.proof.role == requiredRole && $0.requiredForOperationalUse
                    })
            })
        }

        private var requiredSourceRoles: [SourceRole] {
            switch plan.identity.mode {
            case .truck:
                return [.routeEngine, .constraint, .regulatory, .validation]
            case .rail, .vessel:
                return [.routeEngine, .graph, .constraint, .regulatory, .validation]
            }
        }

        private func sourceRoleIsCompatible(_ source: SourceProof) -> Bool {
            switch source.role {
            case .routeEngine, .graph:
                return source.sourceRole == .foundationGraph
            case .constraint:
                return source.sourceRole == .operationalConstraint
            case .regulatory:
                return source.sourceRole == .regulatory
            case .trafficWeather:
                return source.sourceRole == .trafficWeather
            case .validation:
                return source.sourceRole != .observation &&
                    source.sourceRole != .displayOnly
            }
        }

        private func sourceWindowCoversPlan(_ source: SourceProof) -> Bool {
            guard let retrievedAt = parseInstant(source.retrievedAt),
                  let effectiveRaw = source.effectiveAt,
                  let expiresRaw = source.expiresAt,
                  let effectiveAt = parseInstant(effectiveRaw),
                  let expiresAt = parseInstant(expiresRaw),
                  let planFrom = parseInstant(plan.validFrom),
                  let planUntilRaw = plan.validUntil,
                  let planUntil = parseInstant(planUntilRaw),
                  expiresAt > effectiveAt,
                  expiresAt > retrievedAt,
                  effectiveAt <= planFrom,
                  expiresAt >= planUntil,
                  expiresAt > Date() else { return false }
            return true
        }

        private func segmentEvidenceIsCoherent(expectedDistance: Int) -> Bool {
            let sourceIDs = Set(plan.sources.map(\.sourceSnapshotId.rawValue))
            var accumulated = 0
            for segment in plan.segments {
                guard segment.distanceMeters >= 0,
                      segment.durationSeconds.map({ $0 >= 0 }) ?? true,
                      segment.cumulativeStartMeters == accumulated,
                      segment.cumulativeEndMeters >= segment.cumulativeStartMeters,
                      segment.cumulativeEndMeters - segment.cumulativeStartMeters ==
                        segment.distanceMeters,
                      sourceIDs.contains(segment.sourceSnapshotId.rawValue),
                      canonicalText(segment.stableEdgeId),
                      segment.operatorRef.map(canonicalText) ?? true,
                      segment.logisticsEdgeId.map({ $0 > 0 }) ?? true,
                      segment.fromNodeId.map({ $0 > 0 }) ?? true,
                      segment.toNodeId.map({ $0 > 0 }) ?? true else { return false }
                let (next, overflow) = accumulated.addingReportingOverflow(segment.distanceMeters)
                guard !overflow else { return false }
                accumulated = next
            }
            return accumulated == expectedDistance &&
                plan.segments.last?.cumulativeEndMeters == expectedDistance
        }

        private var instructionEvidenceIsCoherent: Bool {
            guard plan.purpose != .activeJob || !plan.instructions.isEmpty else { return false }
            return plan.instructions.allSatisfy({ instruction in
                canonicalText(instruction.instructionType) &&
                    canonicalText(instruction.title) &&
                    canonicalText(instruction.visualText) &&
                    canonicalText(instruction.spokenText) &&
                    canonicalText(instruction.accessibilityText) &&
                    (instruction.triggerDistanceMeters.map({ $0 >= 0 }) ?? true) &&
                    (instruction.courseDegrees.map({ $0.isFinite && $0 >= 0 && $0 < 360 }) ?? true)
            })
        }

        private var constraintEvidenceIsCoherent: Bool {
            let prefix = "\(plan.identity.mode.rawValue.lowercased())."
            let decisiveOutcomes: [ConstraintOutcome] = [.applied, .cleared, .warning]
            guard plan.constraints.allSatisfy({ constraint in
                canonicalText(constraint.constraintType) &&
                    constraint.constraintType.hasPrefix(prefix) &&
                    decisiveOutcomes.contains(constraint.outcome) &&
                    constraint.requiredValue.map(canonicalText) ?? true &&
                    constraint.observedValue.map(canonicalText) ?? true &&
                    constraint.unit.map(canonicalText) ?? true &&
                    constraint.legalReference.map(canonicalText) ?? true &&
                    plan.sources.contains(where: { source in
                        source.sourceSnapshotId == constraint.sourceSnapshotId &&
                            [.constraint, .regulatory, .validation].contains(source.role)
                    })
            }) else { return false }

            let requiredPrefixes: [String]
            switch plan.identity.mode {
            case .truck:
                requiredPrefixes = ["truck.profile.", "truck.network.", "truck.regulatory."]
            case .rail:
                requiredPrefixes = [
                    "rail.profile.", "rail.network.", "rail.regulatory.",
                    "rail.operational.",
                ]
            case .vessel:
                requiredPrefixes = [
                    "vessel.profile.", "vessel.network.", "vessel.regulatory.",
                    "vessel.environmental.",
                ]
            }
            return requiredPrefixes.allSatisfy({ requiredPrefix in
                plan.constraints.contains(where: {
                    $0.constraintType.hasPrefix(requiredPrefix) &&
                        decisiveOutcomes.contains($0.outcome)
                })
            })
        }

        private func canonicalText(_ value: String) -> Bool {
            guard !value.isEmpty,
                  value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !value.unicodeScalars.contains(where: { scalar in
                let value = scalar.value
                return value <= 8 || value == 11 || value == 12 ||
                    (14...31).contains(value) || value == 127
            })
        }

        private func parseInstant(_ value: String) -> Date? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let wholeSeconds = ISO8601DateFormatter()
            wholeSeconds.formatOptions = [.withInternetDateTime]
            return wholeSeconds.date(from: value)
        }
    }

    struct Blocker: Decodable, Equatable, Sendable {
        let code: BlockerCode
        let path: String
        let message: String
        let evidenceKind: EvidenceKind?
    }

    struct PersistedMutation: Equatable, Sendable {
        let state: VersionState
        let operational: Bool
        let route: BoundRoutePlan
    }

    struct PendingMutation: Equatable, Sendable {
        let state: VersionState
        let operational: Bool
        let reasonCode: PendingReasonCode
        let blockers: [Blocker]
    }

    enum PlanMutationResult: Decodable, Equatable, Sendable {
        case persisted(PersistedMutation)
        case pending(PendingMutation)

        private enum CodingKeys: String, CodingKey {
            case persisted
            case state
            case operational
            case route
            case reasonCode
            case blockers
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let persisted = try container.decode(Bool.self, forKey: .persisted)
            let state = try container.decode(VersionState.self, forKey: .state)
            let operational = try container.decode(Bool.self, forKey: .operational)

            if persisted {
                guard !container.contains(.reasonCode),
                      !container.contains(.blockers) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .persisted,
                        in: container,
                        debugDescription: "Persisted route result cannot carry unpersisted blockers"
                    )
                }
                let route = try container.decode(BoundRoutePlan.self, forKey: .route)
                guard route.plan.state == state,
                      route.plan.operational == operational else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .state,
                        in: container,
                        debugDescription: "Mutation truth differs from its exact persisted route"
                    )
                }
                self = .persisted(.init(
                    state: state,
                    operational: operational,
                    route: route
                ))
            } else {
                guard state == .routePending,
                      operational == false,
                      container.contains(.route),
                      try container.decodeNil(forKey: .route) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .route,
                        in: container,
                        debugDescription: "Unpersisted result must be an explicit route_pending with null route"
                    )
                }
                self = .pending(.init(
                    state: state,
                    operational: operational,
                    reasonCode: try container.decode(PendingReasonCode.self, forKey: .reasonCode),
                    blockers: try container.decode([Blocker].self, forKey: .blockers)
                ))
            }
        }

        var boundRoute: BoundRoutePlan? {
            guard case .persisted(let value) = self else { return nil }
            return value.route
        }

        var rendererPayload: BoundRoutePlan.RendererPayload? {
            boundRoute?.rendererPayload
        }
    }

    enum ClientError: LocalizedError, Equatable {
        case invalidSubjectID
        case executionIdentityMismatch

        var errorDescription: String? {
            switch self {
            case .invalidSubjectID:
                return "This route is not linked to a valid load or shipment."
            case .executionIdentityMismatch:
                return "Live route evidence did not match the exact assigned route execution."
            }
        }
    }

    private struct SubjectWire: Encodable {
        let type: String
        let id: Int
    }

    private struct PlanInput: Encodable {
        let subject: SubjectWire
        let purpose: String
    }

    private struct BoundSubjectInput: Encodable {
        let by = "subject"
        let subject: SubjectWire
    }

    private struct BoundBindingInput: Encodable {
        let by = "binding"
        let bindingPublicId: String
    }

    private struct ExecutionAssignmentInput: Encodable {
        let subject: SubjectWire
        let requestId: String
    }

    private struct ExecutionMemberInput: Encodable {
        let assignmentPublicId: String
        let requestId: String
    }

    private struct ExecutionStateInput: Encodable {
        let assignmentPublicId: String
    }

    private let api: EusoTripAPI

    init(api: EusoTripAPI) {
        self.api = api
    }

    func plan(subject: Subject, purpose: Purpose) async throws -> PlanMutationResult {
        try await api.mutation(
            "route.plan",
            input: PlanInput(
                subject: try subjectWire(subject),
                purpose: purpose.rawValue
            )
        )
    }

    func planLoad(id: Int, purpose: Purpose) async throws -> PlanMutationResult {
        try await plan(subject: .load(id), purpose: purpose)
    }

    func planRailShipment(id: Int, purpose: Purpose) async throws -> PlanMutationResult {
        try await plan(subject: .railShipment(id), purpose: purpose)
    }

    func planVesselShipment(id: Int, purpose: Purpose) async throws -> PlanMutationResult {
        try await plan(subject: .vesselShipment(id), purpose: purpose)
    }

    func planVesselVoyage(id: Int, purpose: Purpose) async throws -> PlanMutationResult {
        try await plan(subject: .vesselVoyage(id), purpose: purpose)
    }

    func getBound(subject: Subject) async throws -> BoundRoutePlan {
        try await api.query(
            "route.getBound",
            input: BoundSubjectInput(subject: try subjectWire(subject))
        )
    }

    func getBound(bindingPublicID: UUID) async throws -> BoundRoutePlan {
        try await api.query(
            "route.getBound",
            input: BoundBindingInput(
                bindingPublicId: bindingPublicID.uuidString.lowercased()
            )
        )
    }

    func getBoundLoad(id: Int) async throws -> BoundRoutePlan {
        try await getBound(subject: .load(id))
    }

    func getBoundRailShipment(id: Int) async throws -> BoundRoutePlan {
        try await getBound(subject: .railShipment(id))
    }

    func getBoundVesselShipment(id: Int) async throws -> BoundRoutePlan {
        try await getBound(subject: .vesselShipment(id))
    }

    func getBoundVesselVoyage(id: Int) async throws -> BoundRoutePlan {
        try await getBound(subject: .vesselVoyage(id))
    }

    func assignExecution(subject: Subject) async throws -> ExecutionAssignmentResult {
        try await api.mutation(
            "route.assignExecution",
            input: ExecutionAssignmentInput(
                subject: try subjectWire(subject),
                requestId: UUID().uuidString.lowercased()
            )
        )
    }

    @discardableResult
    func synchronizeExecution(
        assignmentPublicID: PublicUUID
    ) async throws -> ExecutionSynchronizationResult {
        try await api.mutation(
            "route.synchronizeExecution",
            input: ExecutionMemberInput(
                assignmentPublicId: assignmentPublicID.rawValue,
                requestId: UUID().uuidString.lowercased()
            )
        )
    }

    func getExecutionState(
        assignmentPublicID: PublicUUID
    ) async throws -> ExecutionState {
        try await api.query(
            "route.getExecutionState",
            input: ExecutionStateInput(
                assignmentPublicId: assignmentPublicID.rawValue
            )
        )
    }

    /// Assigns the exact bound mode asset, consumes at most one new licensed
    /// server-side observation, then reads the fail-closed projected state.
    /// No client coordinate, mileage, progress, ETA, speed, course, provider,
    /// instruction, safety, or Haul claim crosses this boundary.
    func refreshExecution(subject: Subject) async throws -> ExecutionState {
        let assignment = try await assignExecution(subject: subject)
        _ = try await synchronizeExecution(
            assignmentPublicID: assignment.assignment.publicId
        )
        let state = try await getExecutionState(
            assignmentPublicID: assignment.assignment.publicId
        )
        guard state.mode == assignment.mode,
              state.assignment.publicId == assignment.assignment.publicId else {
            throw ClientError.executionIdentityMismatch
        }
        return state
    }

    private func subjectWire(_ subject: Subject) throws -> SubjectWire {
        guard subject.id > 0,
              subject.id <= Self.maximumSafeJSONInteger else {
            throw ClientError.invalidSubjectID
        }
        return SubjectWire(type: subject.wireType, id: subject.id)
    }

    nonisolated private static func parseInstant(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }
}
