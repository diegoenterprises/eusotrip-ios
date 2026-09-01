//
//  CanonicalRoutePackageStore.swift
//  EusoTrip
//
//  Atomic tenant/user/load-scoped persistence for server-canonical route
//  packages. Stale packages remain observable as stale; they are never
//  relabeled as live or replaced with a local rail/vessel calculation.
//

import CryptoKit
import Foundation

private enum CanonicalRouteLimits {
    static let signedPayloadBytes = 8 * 1_024 * 1_024
    static let persistedEnvelopeBytes = 12 * 1_024 * 1_024
    static let identifierBytes = 256
    static let segmentCoordinates = 10_000
    static let packageSegments = 1_000
    static let packageCoordinates = 100_000
    static let packageInstructions = 10_000
    static let instructionTextBytes = 4_096
}

/// A route store is a single-writer authority for one persistence root. Actor
/// isolation only serializes one actor instance, so a process-wide lease keeps
/// multiple scenes or composition roots from creating competing writers for
/// the same on-device cache.
private final class CanonicalRouteStoreRootLeaseRegistry: @unchecked Sendable {
    static let shared = CanonicalRouteStoreRootLeaseRegistry()

    private let lock = NSLock()
    private var leasedRoots: Set<String> = []

    func acquire(for rootDirectory: URL) throws -> CanonicalRouteStoreRootLease {
        let rootKey = rootDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        lock.lock()
        defer { lock.unlock() }
        guard leasedRoots.insert(rootKey).inserted else {
            throw CanonicalRouteStoreError.invalidPolicy(
                "Only one app-scoped canonical route store may own a persistence root."
            )
        }
        return CanonicalRouteStoreRootLease(rootKey: rootKey)
    }

    fileprivate func release(rootKey: String) {
        lock.lock()
        leasedRoots.remove(rootKey)
        lock.unlock()
    }
}

private final class CanonicalRouteStoreRootLease: @unchecked Sendable {
    private let rootKey: String

    fileprivate init(rootKey: String) {
        self.rootKey = rootKey
    }

    deinit {
        CanonicalRouteStoreRootLeaseRegistry.shared.release(rootKey: rootKey)
    }
}

struct CanonicalRouteScope: Hashable, Codable, Sendable {
    let tenantID: String
    let userID: String
    let loadID: String

    init(tenantID: String, userID: String, loadID: String) throws {
        self.tenantID = try Self.validated(tenantID, field: "tenant")
        self.userID = try Self.validated(userID, field: "user")
        self.loadID = try Self.validated(loadID, field: "load")
    }

    private enum CodingKeys: String, CodingKey {
        case tenantID, userID, loadID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                tenantID: container.decode(String.self, forKey: .tenantID),
                userID: container.decode(String.self, forKey: .userID),
                loadID: container.decode(String.self, forKey: .loadID)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .loadID,
                in: container,
                debugDescription: "Canonical route scope is invalid."
            )
        }
    }

    private static func validated(_ rawValue: String, field: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw CanonicalRouteStoreError.invalidPackage("The \(field) scope identifier cannot be empty.")
        }
        guard value.utf8.count <= 128 else {
            throw CanonicalRouteStoreError.invalidPackage("The \(field) scope identifier is too long.")
        }
        return value
    }
}

struct CanonicalRouteSummary: Hashable, Codable, Sendable {
    let distanceMeters: Int64
    let durationSeconds: Int64?

    init(distanceMeters: Int64, durationSeconds: Int64?) throws {
        guard distanceMeters >= 0 else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical route distance cannot be negative.")
        }
        if let durationSeconds, durationSeconds < 0 {
            throw CanonicalRouteStoreError.invalidPackage("Canonical route duration cannot be negative.")
        }
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case distanceMeters, durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                distanceMeters: container.decode(Int64.self, forKey: .distanceMeters),
                durationSeconds: container.decodeIfPresent(Int64.self, forKey: .durationSeconds)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .distanceMeters,
                in: container,
                debugDescription: "Canonical route summary is invalid."
            )
        }
    }
}

struct CanonicalRouteGeometrySegment: Hashable, Codable, Sendable {
    let id: String
    let sequence: Int
    let mode: OfflineRouteMode
    let coordinates: [OfflineGeoCoordinate]

    init(
        id: String,
        sequence: Int,
        mode: OfflineRouteMode,
        coordinates: [OfflineGeoCoordinate]
    ) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanonicalRouteStoreError.invalidPackage("A canonical route segment identifier cannot be empty.")
        }
        guard id.utf8.count <= CanonicalRouteLimits.identifierBytes else {
            throw CanonicalRouteStoreError.invalidPackage("A canonical route segment identifier is too long.")
        }
        guard sequence >= 0 else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical route segment sequence cannot be negative.")
        }
        guard coordinates.count >= 2 else {
            throw CanonicalRouteStoreError.invalidPackage("A canonical route segment needs at least two coordinates.")
        }
        guard coordinates.count <= CanonicalRouteLimits.segmentCoordinates else {
            throw CanonicalRouteStoreError.invalidPackage("A canonical route segment contains too many coordinates.")
        }
        self.id = id
        self.sequence = sequence
        self.mode = mode
        self.coordinates = coordinates
    }

    private enum CodingKeys: String, CodingKey {
        case id, sequence, mode, coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: container.decode(String.self, forKey: .id),
                sequence: container.decode(Int.self, forKey: .sequence),
                mode: container.decode(OfflineRouteMode.self, forKey: .mode),
                coordinates: container.decode([OfflineGeoCoordinate].self, forKey: .coordinates)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .coordinates,
                in: container,
                debugDescription: "Canonical route segment is invalid."
            )
        }
    }
}

struct CanonicalRouteInstruction: Hashable, Codable, Sendable {
    let sequence: Int
    let text: String
    let coordinate: OfflineGeoCoordinate?

    init(sequence: Int, text: String, coordinate: OfflineGeoCoordinate?) throws {
        guard sequence >= 0 else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical instruction sequence cannot be negative.")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical instruction text cannot be empty.")
        }
        guard text.utf8.count <= CanonicalRouteLimits.instructionTextBytes else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical instruction text is too long.")
        }
        self.sequence = sequence
        self.text = text
        self.coordinate = coordinate
    }

    private enum CodingKeys: String, CodingKey {
        case sequence, text, coordinate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sequence: container.decode(Int.self, forKey: .sequence),
                text: container.decode(String.self, forKey: .text),
                coordinate: container.decodeIfPresent(OfflineGeoCoordinate.self, forKey: .coordinate)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .text,
                in: container,
                debugDescription: "Canonical route instruction is invalid."
            )
        }
    }
}

enum CanonicalRouteSignatureAlgorithm: String, Codable, Sendable {
    case ed25519
}

/// Exact bytes and detached signature returned by the authenticated
/// `route.plan` response. EusoTrip never derives server-canonical authority
/// from locally assembled geometry.
struct CanonicalRouteSignedEnvelope: Hashable, Codable, Sendable {
    let keyID: String
    let algorithm: CanonicalRouteSignatureAlgorithm
    let payload: Data
    let signature: Data

    init(
        keyID: String,
        algorithm: CanonicalRouteSignatureAlgorithm,
        payload: Data,
        signature: Data
    ) throws {
        let keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty, keyID.utf8.count <= 128 else {
            throw CanonicalRouteStoreError.invalidPackage("The route signing key identifier is invalid.")
        }
        guard !payload.isEmpty else {
            throw CanonicalRouteStoreError.invalidPackage("The signed route payload is empty.")
        }
        guard payload.count <= CanonicalRouteLimits.signedPayloadBytes else {
            throw CanonicalRouteStoreError.invalidPackage("The signed route payload exceeds the safe byte limit.")
        }
        guard signature.count == 64 else {
            throw CanonicalRouteStoreError.invalidPackage("The Ed25519 route signature has an invalid length.")
        }
        self.keyID = keyID
        self.algorithm = algorithm
        self.payload = payload
        self.signature = signature
    }

    private enum CodingKeys: String, CodingKey {
        case keyID, algorithm, payload, signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                keyID: container.decode(String.self, forKey: .keyID),
                algorithm: container.decode(CanonicalRouteSignatureAlgorithm.self, forKey: .algorithm),
                payload: container.decode(Data.self, forKey: .payload),
                signature: container.decode(Data.self, forKey: .signature)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .signature,
                in: container,
                debugDescription: "The signed canonical-route envelope is invalid."
            )
        }
    }
}

struct CanonicalRouteVerificationKey: Hashable, Sendable {
    let keyID: String
    let ed25519RawRepresentation: Data

    init(keyID: String, ed25519RawRepresentation: Data) throws {
        let keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty, keyID.utf8.count <= 128 else {
            throw CanonicalRouteStoreError.invalidPolicy("A route verification key identifier is invalid.")
        }
        do {
            _ = try Curve25519.Signing.PublicKey(rawRepresentation: ed25519RawRepresentation)
        } catch {
            throw CanonicalRouteStoreError.invalidPolicy("An Ed25519 route verification key is invalid.")
        }
        self.keyID = keyID
        self.ed25519RawRepresentation = ed25519RawRepresentation
    }
}

/// Claims and route content covered by the server signature. The scope is part
/// of the signed bytes, so tenant/user/load identity cannot be substituted by
/// the device after the response is received.
struct CanonicalRouteSignedPayload: Hashable, Codable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let issuer: String
    let audience: String
    let scope: CanonicalRouteScope
    let routeID: String
    let serverRevision: String
    let mode: OfflineRouteMode
    /// Server-signed response issuance time. Offline freshness is based on
    /// this claim, never on a caller-provided local observation timestamp.
    let issuedAt: Date
    let generatedAt: Date
    let validUntil: Date?
    let summary: CanonicalRouteSummary
    let segments: [CanonicalRouteGeometrySegment]
    let instructions: [CanonicalRouteInstruction]

    init(
        issuer: String,
        audience: String,
        scope: CanonicalRouteScope,
        routeID: String,
        serverRevision: String,
        mode: OfflineRouteMode,
        issuedAt: Date,
        generatedAt: Date,
        validUntil: Date?,
        summary: CanonicalRouteSummary,
        segments: [CanonicalRouteGeometrySegment],
        instructions: [CanonicalRouteInstruction]
    ) throws {
        let issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let audience = audience.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !issuer.isEmpty, issuer.utf8.count <= 256,
              !audience.isEmpty, audience.utf8.count <= 256 else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical route issuer or audience is invalid.")
        }
        guard !routeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical route identifier cannot be empty.")
        }
        guard routeID.utf8.count <= CanonicalRouteLimits.identifierBytes else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical route identifier is too long.")
        }
        guard !serverRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical server revision cannot be empty.")
        }
        guard serverRevision.utf8.count <= CanonicalRouteLimits.identifierBytes else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical server revision is too long.")
        }
        guard issuedAt.timeIntervalSince1970.isFinite,
              generatedAt.timeIntervalSince1970.isFinite else {
            throw CanonicalRouteStoreError.invalidPackage("Canonical route issuance or generation time is invalid.")
        }
        if let validUntil {
            guard validUntil.timeIntervalSince1970.isFinite else {
                throw CanonicalRouteStoreError.invalidPackage("Canonical route validity time is invalid.")
            }
        }
        if let validUntil, validUntil < generatedAt {
            throw CanonicalRouteStoreError.invalidPackage("Canonical route validity cannot end before generation.")
        }
        guard !segments.isEmpty else {
            throw CanonicalRouteStoreError.invalidPackage("A canonical route package must include geometry.")
        }
        guard segments.count <= CanonicalRouteLimits.packageSegments,
              instructions.count <= CanonicalRouteLimits.packageInstructions,
              segments.reduce(into: 0, { $0 += $1.coordinates.count }) <= CanonicalRouteLimits.packageCoordinates else {
            throw CanonicalRouteStoreError.invalidPackage(
                "The canonical route package exceeds safe geometry or instruction limits."
            )
        }
        guard segments.allSatisfy({ $0.mode == mode }) else {
            throw CanonicalRouteStoreError.invalidPackage(
                "Every canonical route segment must match the signed package mode."
            )
        }
        let segmentSequences = segments.map(\.sequence)
        guard segmentSequences == segmentSequences.sorted(),
              Set(segmentSequences).count == segmentSequences.count else {
            throw CanonicalRouteStoreError.invalidPackage(
                "Canonical route segments must have unique, ascending sequence numbers."
            )
        }
        let instructionSequences = instructions.map(\.sequence)
        guard instructionSequences == instructionSequences.sorted(),
              Set(instructionSequences).count == instructionSequences.count else {
            throw CanonicalRouteStoreError.invalidPackage(
                "Canonical route instructions must have unique, ascending sequence numbers."
            )
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.issuer = issuer
        self.audience = audience
        self.scope = scope
        self.routeID = routeID
        self.serverRevision = serverRevision
        self.mode = mode
        self.issuedAt = issuedAt
        self.generatedAt = generatedAt
        self.validUntil = validUntil
        self.summary = summary
        self.segments = segments
        self.instructions = instructions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, issuer, audience, scope, routeID, serverRevision, mode, issuedAt, generatedAt
        case validUntil, summary, segments, instructions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported canonical route package schema."
            )
        }
        do {
            try self.init(
                issuer: container.decode(String.self, forKey: .issuer),
                audience: container.decode(String.self, forKey: .audience),
                scope: container.decode(CanonicalRouteScope.self, forKey: .scope),
                routeID: container.decode(String.self, forKey: .routeID),
                serverRevision: container.decode(String.self, forKey: .serverRevision),
                mode: container.decode(OfflineRouteMode.self, forKey: .mode),
                issuedAt: container.decode(Date.self, forKey: .issuedAt),
                generatedAt: container.decode(Date.self, forKey: .generatedAt),
                validUntil: container.decodeIfPresent(Date.self, forKey: .validUntil),
                summary: container.decode(CanonicalRouteSummary.self, forKey: .summary),
                segments: container.decode([CanonicalRouteGeometrySegment].self, forKey: .segments),
                instructions: container.decode([CanonicalRouteInstruction].self, forKey: .instructions)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .routeID,
                in: container,
                debugDescription: "Canonical route package failed validation."
            )
        }
    }
}

/// A package exists only after a pinned key verifies the exact route.plan
/// payload and its signed tenant/user/load claims. Persisted packages retain
/// the signed envelope so the store can reverify them on every read.
struct CanonicalRoutePackage: Hashable, Sendable {
    let signedEnvelope: CanonicalRouteSignedEnvelope
    fileprivate let signedPayload: CanonicalRouteSignedPayload

    var schemaVersion: Int { signedPayload.schemaVersion }
    var scope: CanonicalRouteScope { signedPayload.scope }
    var routeID: String { signedPayload.routeID }
    var serverRevision: String { signedPayload.serverRevision }
    var mode: OfflineRouteMode { signedPayload.mode }
    var issuedAt: Date { signedPayload.issuedAt }
    var generatedAt: Date { signedPayload.generatedAt }
    var validUntil: Date? { signedPayload.validUntil }
    var summary: CanonicalRouteSummary { signedPayload.summary }
    var segments: [CanonicalRouteGeometrySegment] { signedPayload.segments }
    var instructions: [CanonicalRouteInstruction] { signedPayload.instructions }
    var provenance: RoutePlanProvenance { .serverCanonical }

    fileprivate init(
        signedEnvelope: CanonicalRouteSignedEnvelope,
        signedPayload: CanonicalRouteSignedPayload
    ) {
        self.signedEnvelope = signedEnvelope
        self.signedPayload = signedPayload
    }
}

struct CanonicalRoutePlanVerifier: Sendable {
    private let expectedIssuer: String
    private let expectedAudience: String
    private let keysByID: [String: Data]

    init(
        expectedIssuer: String,
        expectedAudience: String,
        keys: [CanonicalRouteVerificationKey]
    ) throws {
        let issuer = expectedIssuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let audience = expectedAudience.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !issuer.isEmpty, !audience.isEmpty else {
            throw CanonicalRouteStoreError.invalidPolicy(
                "Canonical route issuer and audience must be pinned."
            )
        }
        let pairs = keys.map { ($0.keyID, $0.ed25519RawRepresentation) }
        guard !pairs.isEmpty, Set(pairs.map(\.0)).count == pairs.count else {
            throw CanonicalRouteStoreError.invalidPolicy(
                "Canonical route verification keys must be non-empty and unique."
            )
        }
        self.expectedIssuer = issuer
        self.expectedAudience = audience
        keysByID = Dictionary(uniqueKeysWithValues: pairs)
    }

    func verify(
        _ envelope: CanonicalRouteSignedEnvelope,
        expectedScope: CanonicalRouteScope
    ) throws -> CanonicalRoutePackage {
        guard envelope.algorithm == .ed25519,
              let rawKey = keysByID[envelope.keyID] else {
            throw CanonicalRouteStoreError.untrustedSigningKey
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
        } catch {
            throw CanonicalRouteStoreError.untrustedSigningKey
        }
        guard publicKey.isValidSignature(envelope.signature, for: envelope.payload) else {
            throw CanonicalRouteStoreError.invalidSignature
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: CanonicalRouteSignedPayload
        do {
            payload = try decoder.decode(CanonicalRouteSignedPayload.self, from: envelope.payload)
        } catch {
            throw CanonicalRouteStoreError.decodingFailed
        }
        guard payload.issuer == expectedIssuer,
              payload.audience == expectedAudience,
              payload.scope == expectedScope else {
            throw CanonicalRouteStoreError.signedClaimMismatch
        }
        return CanonicalRoutePackage(signedEnvelope: envelope, signedPayload: payload)
    }

    func reverify(_ package: CanonicalRoutePackage) throws {
        let verified = try verify(package.signedEnvelope, expectedScope: package.scope)
        guard verified == package else {
            throw CanonicalRouteStoreError.invalidSignature
        }
    }
}

struct CanonicalRouteFreshnessPolicy: Equatable, Sendable {
    let maximumServerObservationAge: TimeInterval
    let allowedClockSkew: TimeInterval

    init(maximumServerObservationAge: TimeInterval, allowedClockSkew: TimeInterval = 300) throws {
        guard maximumServerObservationAge.isFinite, maximumServerObservationAge > 0 else {
            throw CanonicalRouteStoreError.invalidPolicy("Maximum server observation age must be positive.")
        }
        guard allowedClockSkew.isFinite, allowedClockSkew >= 0 else {
            throw CanonicalRouteStoreError.invalidPolicy("Allowed clock skew cannot be negative.")
        }
        self.maximumServerObservationAge = maximumServerObservationAge
        self.allowedClockSkew = allowedClockSkew
    }
}

enum CanonicalRouteStalenessReason: Equatable, Sendable {
    case serverObservationTooOld(age: TimeInterval, maximumAge: TimeInterval)
    case routeValidityExpired(Date)
    case observationTimestampInFuture(Date)
    case trustedTimeUnavailable(CanonicalRouteTrustedTimeFailure)
}

enum CanonicalRouteObservationStatus: Equatable, Sendable {
    case missing
    case fresh
    case stale([CanonicalRouteStalenessReason])
}

struct CanonicalRouteObservation: Equatable, Sendable {
    let scope: CanonicalRouteScope
    let package: CanonicalRoutePackage?
    let status: CanonicalRouteObservationStatus
    let lastServerObservedAt: Date?
    let storedAt: Date?
    let observedAt: Date
}

enum CanonicalRouteStoreError: Error, Equatable, Sendable {
    case invalidPolicy(String)
    case invalidPackage(String)
    case persistenceFailed(String)
    case decodingFailed
    case scopeMismatch
    case packageMissing
    case serverRevisionMismatch(expected: String, actual: String)
    case untrustedSigningKey
    case invalidSignature
    case signedClaimMismatch
    case staleSignedRouteReplay
    case trustedTimeUnavailable
}

extension CanonicalRouteStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidPolicy(let message), .invalidPackage(let message), .persistenceFailed(let message):
            return message
        case .decodingFailed:
            return "The cached canonical route package is unreadable."
        case .scopeMismatch:
            return "The cached canonical route belongs to a different tenant, user, or load."
        case .packageMissing:
            return "No cached canonical route package exists for this load."
        case .serverRevisionMismatch:
            return "The cached canonical route revision changed before observation was recorded."
        case .untrustedSigningKey:
            return "The canonical route was signed by an untrusted server key."
        case .invalidSignature:
            return "The canonical route server signature is invalid."
        case .signedClaimMismatch:
            return "The signed canonical route claims do not match this tenant, user, or load."
        case .staleSignedRouteReplay:
            return "An older or conflicting signed canonical route response cannot replace the cached route."
        case .trustedTimeUnavailable:
            return "Canonical route time could not be anchored to authenticated server evidence."
        }
    }
}

actor CanonicalRoutePackageStore {
    private struct StoredEnvelope: Codable {
        static let currentSchemaVersion = 6

        let schemaVersion: Int
        let signedEnvelope: CanonicalRouteSignedEnvelope
        let receivedAtEpochSeconds: TimeInterval
        let storedAtEpochSeconds: TimeInterval

        var receivedAt: Date {
            Date(timeIntervalSince1970: receivedAtEpochSeconds)
        }

        var storedAt: Date {
            Date(timeIntervalSince1970: storedAtEpochSeconds)
        }

        init(package: CanonicalRoutePackage, receivedAt: Date, storedAt: Date) {
            schemaVersion = Self.currentSchemaVersion
            signedEnvelope = package.signedEnvelope
            receivedAtEpochSeconds = receivedAt.timeIntervalSince1970
            storedAtEpochSeconds = storedAt.timeIntervalSince1970
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, signedEnvelope, receivedAtEpochSeconds, storedAtEpochSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == Self.currentSchemaVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported route store envelope schema."
                )
            }
            signedEnvelope = try container.decode(CanonicalRouteSignedEnvelope.self, forKey: .signedEnvelope)
            receivedAtEpochSeconds = try container.decode(
                TimeInterval.self,
                forKey: .receivedAtEpochSeconds
            )
            storedAtEpochSeconds = try container.decode(TimeInterval.self, forKey: .storedAtEpochSeconds)
            guard receivedAtEpochSeconds.isFinite, storedAtEpochSeconds.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .storedAtEpochSeconds,
                    in: container,
                    debugDescription: "Canonical route receipt or storage time is invalid."
                )
            }
        }
    }

    private struct VerifiedEnvelope {
        let package: CanonicalRoutePackage
        let serverIssuedAt: Date
        let receivedAt: Date
        let storedAt: Date

        init(package: CanonicalRoutePackage, receivedAt: Date, storedAt: Date) {
            self.package = package
            serverIssuedAt = package.issuedAt
            self.receivedAt = receivedAt
            self.storedAt = storedAt
        }
    }

    private let rootDirectory: URL
    private let rootLease: CanonicalRouteStoreRootLease
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let verifier: CanonicalRoutePlanVerifier
    private let trustedClock: CanonicalRouteTrustedClock
    private let maximumFutureTimestampSkew: TimeInterval
    private let maximumRouteValidityHorizon: TimeInterval
    /// Diagnostic wall time only. Route age and expiry never use this clock.
    private let currentTime: @Sendable () -> Date

    init(
        rootDirectory: URL,
        verifier: CanonicalRoutePlanVerifier,
        fileManager: FileManager = .default,
        maximumFutureTimestampSkew: TimeInterval = 300,
        maximumRouteValidityHorizon: TimeInterval = 7 * 24 * 60 * 60,
        trustedClock: CanonicalRouteTrustedClock = CanonicalRouteTrustedClock(),
        currentTime: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        guard maximumFutureTimestampSkew.isFinite,
              maximumFutureTimestampSkew >= 0 else {
            throw CanonicalRouteStoreError.invalidPolicy(
                "Canonical route future timestamp skew must be finite and non-negative."
            )
        }
        guard maximumRouteValidityHorizon.isFinite,
              maximumRouteValidityHorizon > 0 else {
            throw CanonicalRouteStoreError.invalidPolicy(
                "Canonical route validity horizon must be finite and positive."
            )
        }
        let canonicalRootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        rootLease = try CanonicalRouteStoreRootLeaseRegistry.shared.acquire(
            for: canonicalRootDirectory
        )
        self.rootDirectory = canonicalRootDirectory
        self.fileManager = fileManager
        self.verifier = verifier
        self.trustedClock = trustedClock
        self.maximumFutureTimestampSkew = maximumFutureTimestampSkew
        self.maximumRouteValidityHorizon = maximumRouteValidityHorizon
        self.currentTime = currentTime
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    /// Verifies and atomically replaces one exact scope from the signed
    /// authenticated `route.plan` response.
    @discardableResult
    func store(
        signedEnvelope: CanonicalRouteSignedEnvelope,
        expectedScope: CanonicalRouteScope,
        receivedAt: Date,
        storedAt: Date = Date()
    ) throws -> CanonicalRoutePackage {
        let package = try verifier.verify(signedEnvelope, expectedScope: expectedScope)
        try validateLocalDiagnosticTimestamp(receivedAt, field: "server response receipt")
        try validateLocalDiagnosticTimestamp(storedAt, field: "store")
        try validateTimeline(package: package)

        let principal = CanonicalRoutePrincipal(scope: package.scope)
        let existing = try readEnvelope(for: expectedScope)
        let isNewSignedResponse: Bool
        if let existing {
            guard package.issuedAt >= existing.serverIssuedAt,
                  package.generatedAt >= existing.package.generatedAt else {
                throw CanonicalRouteStoreError.staleSignedRouteReplay
            }
            if package.issuedAt == existing.serverIssuedAt,
               package.signedEnvelope != existing.package.signedEnvelope {
                throw CanonicalRouteStoreError.staleSignedRouteReplay
            }
            isNewSignedResponse = package.issuedAt > existing.serverIssuedAt
        } else {
            isNewSignedResponse = true
        }
        let readingBeforeReceipt = trustedClock.reading(for: principal)
        if case .trusted(let trustedNow) = readingBeforeReceipt,
           package.issuedAt > trustedNow.addingTimeInterval(maximumFutureTimestampSkew) {
            throw CanonicalRouteStoreError.invalidPackage(
                "The canonical route signed server issuance timestamp is implausibly far in the future."
            )
        }

        if isNewSignedResponse {
            do {
                try trustedClock.establishAuthenticatedAnchor(
                    for: principal,
                    signedServerTime: package.issuedAt
                )
            } catch {
                throw CanonicalRouteStoreError.trustedTimeUnavailable
            }
        } else if case .unavailable = readingBeforeReceipt {
            // Persisted signed bytes are not new time evidence. In particular,
            // replaying them after a process restart or reboot must not revive
            // freshness. Keep the already-verified envelope unchanged.
            guard let existing else {
                throw CanonicalRouteStoreError.trustedTimeUnavailable
            }
            return existing.package
        }

        guard case .trusted(let trustedReceiptTime) = trustedClock.reading(for: principal) else {
            throw CanonicalRouteStoreError.trustedTimeUnavailable
        }
        guard package.issuedAt <= trustedReceiptTime.addingTimeInterval(maximumFutureTimestampSkew) else {
            throw CanonicalRouteStoreError.invalidPackage(
                "The canonical route signed server issuance timestamp is implausibly far in the future."
            )
        }
        let envelope = VerifiedEnvelope(
            package: package,
            receivedAt: receivedAt,
            storedAt: storedAt
        )
        try write(envelope, for: package.scope)
        return package
    }

    /// Removes one scoped package. Production logout/account-switch wiring must
    /// call `purgeAllCachedRoutes()` so prior-principal geometry does not linger.
    func purge(scope: CanonicalRouteScope) throws {
        let url = fileURL(for: scope)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw CanonicalRouteStoreError.persistenceFailed(
                "The scoped canonical route package could not be removed."
            )
        }
    }

    func purgeAllCachedRoutes() throws {
        trustedClock.invalidateAll()
        let directory = canonicalRoutesDirectory
        guard fileManager.fileExists(atPath: directory.path) else { return }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw CanonicalRouteStoreError.persistenceFailed(
                "Cached canonical routes could not be removed for the principal transition."
            )
        }
    }

    func observe(
        scope: CanonicalRouteScope,
        policy: CanonicalRouteFreshnessPolicy
    ) throws -> CanonicalRouteObservation {
        let diagnosticWallTime = currentTime()
        guard diagnosticWallTime.timeIntervalSince1970.isFinite else {
            throw CanonicalRouteStoreError.invalidPackage(
                "The canonical route observation time is invalid."
            )
        }
        guard let envelope = try readEnvelope(for: scope) else {
            return CanonicalRouteObservation(
                scope: scope,
                package: nil,
                status: .missing,
                lastServerObservedAt: nil,
                storedAt: nil,
                observedAt: diagnosticWallTime
            )
        }
        guard envelope.package.scope == scope else {
            throw CanonicalRouteStoreError.scopeMismatch
        }

        var reasons: [CanonicalRouteStalenessReason] = []
        let observedAt: Date
        switch trustedClock.reading(for: CanonicalRoutePrincipal(scope: scope)) {
        case .unavailable(let failure):
            observedAt = diagnosticWallTime
            reasons.append(.trustedTimeUnavailable(failure))
        case .trusted(let trustedTime):
            observedAt = trustedTime
            let futureLimit = trustedTime.addingTimeInterval(policy.allowedClockSkew)
            if envelope.serverIssuedAt > futureLimit {
                reasons.append(.observationTimestampInFuture(envelope.serverIssuedAt))
            } else {
                let age = max(0, trustedTime.timeIntervalSince(envelope.serverIssuedAt))
                if age > policy.maximumServerObservationAge {
                    reasons.append(
                        .serverObservationTooOld(
                            age: age,
                            maximumAge: policy.maximumServerObservationAge
                        )
                    )
                }
            }
            if let validUntil = envelope.package.validUntil, trustedTime > validUntil {
                reasons.append(.routeValidityExpired(validUntil))
            }
        }

        return CanonicalRouteObservation(
            scope: scope,
            package: envelope.package,
            status: reasons.isEmpty ? .fresh : .stale(reasons),
            lastServerObservedAt: envelope.serverIssuedAt,
            storedAt: envelope.storedAt,
            observedAt: observedAt
        )
    }

    private func readEnvelope(for scope: CanonicalRouteScope) throws -> VerifiedEnvelope? {
        let url = fileURL(for: scope)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let fileSize = attributes[.size] as? NSNumber,
                  fileSize.intValue <= CanonicalRouteLimits.persistedEnvelopeBytes else {
                throw CanonicalRouteStoreError.decodingFailed
            }
            let storedEnvelope = try decoder.decode(
                StoredEnvelope.self,
                from: Data(contentsOf: url, options: .mappedIfSafe)
            )
            let package = try verifier.verify(storedEnvelope.signedEnvelope, expectedScope: scope)
            try validateLocalDiagnosticTimestamp(
                storedEnvelope.receivedAt,
                field: "cached server response receipt"
            )
            try validateLocalDiagnosticTimestamp(storedEnvelope.storedAt, field: "cached store")
            try validateTimeline(package: package)
            return VerifiedEnvelope(
                package: package,
                receivedAt: storedEnvelope.receivedAt,
                storedAt: storedEnvelope.storedAt
            )
        } catch let error as CanonicalRouteStoreError {
            throw error
        } catch {
            throw CanonicalRouteStoreError.decodingFailed
        }
    }

    private func write(_ envelope: VerifiedEnvelope, for scope: CanonicalRouteScope) throws {
        guard envelope.package.scope == scope else {
            throw CanonicalRouteStoreError.scopeMismatch
        }
        try verifier.reverify(envelope.package)
        let url = fileURL(for: scope)
        do {
            try fileManager.createDirectory(
                at: canonicalRoutesDirectory,
                withIntermediateDirectories: true
            )
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableCanonicalRoutesDirectory = canonicalRoutesDirectory
            try mutableCanonicalRoutesDirectory.setResourceValues(resourceValues)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
#if os(iOS) || os(tvOS) || os(watchOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: canonicalRoutesDirectory.path
            )
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.deletingLastPathComponent().path
            )
#endif
            let data = try encoder.encode(
                StoredEnvelope(
                    package: envelope.package,
                    receivedAt: envelope.receivedAt,
                    storedAt: envelope.storedAt
                )
            )
            guard data.count <= CanonicalRouteLimits.persistedEnvelopeBytes else {
                throw CanonicalRouteStoreError.invalidPackage(
                    "The canonical route package exceeds the on-device persistence limit."
                )
            }
            try data.write(to: url, options: .atomic)
#if os(iOS) || os(tvOS) || os(watchOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
#endif
        } catch let error as CanonicalRouteStoreError {
            throw error
        } catch {
            throw CanonicalRouteStoreError.persistenceFailed(
                "The canonical route package could not be written atomically."
            )
        }
    }

    private func fileURL(for scope: CanonicalRouteScope) -> URL {
        canonicalRoutesDirectory
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("tenant_\(encoded(scope.tenantID))", isDirectory: true)
            .appendingPathComponent("user_\(encoded(scope.userID))", isDirectory: true)
            .appendingPathComponent("load_\(encoded(scope.loadID))", isDirectory: false)
            .appendingPathExtension("json")
    }

    private var canonicalRoutesDirectory: URL {
        rootDirectory.appendingPathComponent("canonical-routes", isDirectory: true)
    }

    /// Base64url prevents caller-controlled identifiers from becoming path
    /// components while remaining deterministic without non-Foundation crypto.
    private func encoded(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func validateLocalDiagnosticTimestamp(_ value: Date, field: String) throws {
        guard value.timeIntervalSince1970.isFinite else {
            throw CanonicalRouteStoreError.invalidPackage(
                "The canonical route \(field) timestamp is invalid."
            )
        }
    }

    private func validateTimeline(package: CanonicalRoutePackage) throws {
        let skew = maximumFutureTimestampSkew
        guard package.generatedAt <= package.issuedAt.addingTimeInterval(skew) else {
            throw CanonicalRouteStoreError.invalidPackage(
                "Canonical route generation and signed server issuance timestamps are inconsistent."
            )
        }
        if let validUntil = package.validUntil {
            guard validUntil >= package.issuedAt.addingTimeInterval(-skew),
                  validUntil.timeIntervalSince(package.generatedAt) <= maximumRouteValidityHorizon else {
                throw CanonicalRouteStoreError.invalidPackage(
                    "Canonical route validity is expired or exceeds the configured safety horizon."
                )
            }
        }
    }
}
