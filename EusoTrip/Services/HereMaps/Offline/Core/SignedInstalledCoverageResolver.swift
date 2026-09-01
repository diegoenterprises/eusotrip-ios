//
//  SignedInstalledCoverageResolver.swift
//  EusoTrip
//
//  Independent, signed installed-region boundary authority. HERE SDK inventory
//  proves which region identifiers are installed; this resolver separately
//  proves what those identifiers cover. Neither source can manufacture the
//  other, and coverage is returned only when both agree on the exact catalog.
//

import CryptoKit
import Foundation

private enum OfflineCoverageLimits {
    static let signedPayloadBytes = 16 * 1_024 * 1_024
    static let persistedEnvelopeBytes = 24 * 1_024 * 1_024
    static let identifierBytes = 256
    static let maximumRegions = 4_096
    static let maximumPolygonsPerRegion = 4_096
    static let maximumRingsPerPolygon = 1_024
    static let maximumCoordinatesPerRing = 100_000
    static let maximumCoordinatesPerManifest = 2_000_000
    static let maximumRequestCoordinates = 250_000
    static let earthRadiusMeters = 6_371_008.8
    static let geometricEpsilon = 1e-10
}

enum OfflineCoverageSignatureAlgorithm: String, Codable, Sendable {
    case ed25519
}

struct OfflineCoverageSignedEnvelope: Hashable, Codable, Sendable {
    let keyID: String
    let algorithm: OfflineCoverageSignatureAlgorithm
    let payload: Data
    let signature: Data

    init(
        keyID: String,
        algorithm: OfflineCoverageSignatureAlgorithm,
        payload: Data,
        signature: Data
    ) throws {
        let keyID = try Self.identifier(keyID, field: "coverage signing key")
        guard !payload.isEmpty, payload.count <= OfflineCoverageLimits.signedPayloadBytes else {
            throw SignedInstalledCoverageError.invalidEnvelope(
                "The signed coverage payload is empty or exceeds the safe byte limit."
            )
        }
        guard signature.count == 64 else {
            throw SignedInstalledCoverageError.invalidEnvelope(
                "The Ed25519 coverage signature has an invalid length."
            )
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
                algorithm: container.decode(OfflineCoverageSignatureAlgorithm.self, forKey: .algorithm),
                payload: container.decode(Data.self, forKey: .payload),
                signature: container.decode(Data.self, forKey: .signature)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .signature,
                in: container,
                debugDescription: "The signed installed-coverage envelope is invalid."
            )
        }
    }

    private static func identifier(_ rawValue: String, field: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= OfflineCoverageLimits.identifierBytes else {
            throw SignedInstalledCoverageError.invalidEnvelope("The \(field) identifier is invalid.")
        }
        return value
    }
}

struct OfflineCoverageVerificationKey: Hashable, Sendable {
    let keyID: String
    let ed25519RawRepresentation: Data

    init(keyID: String, ed25519RawRepresentation: Data) throws {
        let keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty, keyID.utf8.count <= 128 else {
            throw SignedInstalledCoverageError.invalidPolicy(
                "A coverage verification key identifier is invalid."
            )
        }
        do {
            _ = try Curve25519.Signing.PublicKey(rawRepresentation: ed25519RawRepresentation)
        } catch {
            throw SignedInstalledCoverageError.invalidPolicy(
                "An Ed25519 coverage verification key is invalid."
            )
        }
        self.keyID = keyID
        self.ed25519RawRepresentation = ed25519RawRepresentation
    }
}

/// Opaque HERE catalog identity. It is intentionally not parsed into guessed
/// country/state codes; equality must come from the signed dataset and the
/// native installed-inventory adapter.
struct HEREOfflineCatalogVersion: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= 128,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw SignedInstalledCoverageError.invalidManifest(
                "The HERE catalog version is invalid."
            )
        }
        self.rawValue = value
    }

    var description: String { rawValue }

    private init(validatedRawValue: String) {
        rawValue = validatedRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            try self.init(container.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "The HERE catalog version is invalid."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum OfflineCoverageVendor: String, Codable, Sendable {
    case here = "HERE"
}

enum OfflineCoverageProduct: String, Codable, Sendable {
    case hereSDKNavigate = "HERE_SDK_NAVIGATE_IOS"
}

/// Vendor rights and source identity are signed claims. The payload has no
/// tenant or user field because HERE coverage geometry is vendor provenance,
/// not customer authorization data.
struct HEREOfflineCoverageSource: Hashable, Codable, Sendable {
    let vendor: OfflineCoverageVendor
    let product: OfflineCoverageProduct
    let sdkVersion: String
    let rightsID: String
    let rightsHolder: String
    let rightsValidFrom: Date
    let rightsValidUntil: Date

    init(
        sdkVersion: String,
        rightsID: String,
        rightsHolder: String,
        rightsValidFrom: Date,
        rightsValidUntil: Date
    ) throws {
        self.vendor = .here
        self.product = .hereSDKNavigate
        self.sdkVersion = try Self.identifier(sdkVersion, field: "HERE SDK version")
        self.rightsID = try Self.identifier(rightsID, field: "HERE source-rights")
        self.rightsHolder = try Self.identifier(rightsHolder, field: "HERE rights-holder")
        guard rightsValidFrom.timeIntervalSince1970.isFinite,
              rightsValidUntil.timeIntervalSince1970.isFinite,
              rightsValidUntil > rightsValidFrom else {
            throw SignedInstalledCoverageError.invalidManifest(
                "The HERE source-rights validity window is invalid."
            )
        }
        self.rightsValidFrom = rightsValidFrom
        self.rightsValidUntil = rightsValidUntil
    }

    private enum CodingKeys: String, CodingKey {
        case vendor, product, sdkVersion, rightsID, rightsHolder, rightsValidFrom, rightsValidUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(OfflineCoverageVendor.self, forKey: .vendor) == .here,
              try container.decode(OfflineCoverageProduct.self, forKey: .product) == .hereSDKNavigate else {
            throw DecodingError.dataCorruptedError(
                forKey: .vendor,
                in: container,
                debugDescription: "Coverage source is not HERE SDK Navigate for iOS."
            )
        }
        do {
            try self.init(
                sdkVersion: container.decode(String.self, forKey: .sdkVersion),
                rightsID: container.decode(String.self, forKey: .rightsID),
                rightsHolder: container.decode(String.self, forKey: .rightsHolder),
                rightsValidFrom: container.decode(Date.self, forKey: .rightsValidFrom),
                rightsValidUntil: container.decode(Date.self, forKey: .rightsValidUntil)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .rightsID,
                in: container,
                debugDescription: "HERE coverage source-rights claims are invalid."
            )
        }
    }

    private static func identifier(_ rawValue: String, field: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= OfflineCoverageLimits.identifierBytes else {
            throw SignedInstalledCoverageError.invalidManifest("The \(field) claim is invalid.")
        }
        return value
    }
}

/// A closed, simple geographic ring. Dateline crossings are represented by
/// ordinary -180...180 coordinates and unwrapped only for calculations.
struct OfflineCoverageLinearRing: Hashable, Codable, Sendable {
    let coordinates: [OfflineGeoCoordinate]

    init(coordinates: [OfflineGeoCoordinate]) throws {
        guard (4 ... OfflineCoverageLimits.maximumCoordinatesPerRing).contains(coordinates.count),
              coordinates.first == coordinates.last else {
            throw SignedInstalledCoverageError.invalidGeometry(
                "A coverage ring must be closed and contain at least three vertices."
            )
        }
        guard zip(coordinates, coordinates.dropFirst()).allSatisfy({ $0 != $1 }) else {
            throw SignedInstalledCoverageError.invalidGeometry(
                "A coverage ring cannot contain adjacent duplicate coordinates."
            )
        }
        guard Self.absoluteArea(coordinates) > OfflineCoverageLimits.geometricEpsilon else {
            throw SignedInstalledCoverageError.invalidGeometry(
                "A coverage ring must enclose a non-zero area."
            )
        }
        guard Self.isSimple(coordinates) else {
            throw SignedInstalledCoverageError.invalidGeometry(
                "A coverage ring cannot self-intersect."
            )
        }
        self.coordinates = coordinates
    }

    private enum CodingKeys: String, CodingKey { case coordinates }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(coordinates: container.decode([OfflineGeoCoordinate].self, forKey: .coordinates))
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .coordinates,
                in: container,
                debugDescription: "Coverage ring geometry is invalid."
            )
        }
    }

    private static func absoluteArea(_ coordinates: [OfflineGeoCoordinate]) -> Double {
        let points = CoverageGeometry.unwrap(coordinates)
        return abs(zip(points, points.dropFirst()).reduce(0) { partial, pair in
            partial + pair.0.x * pair.1.y - pair.1.x * pair.0.y
        }) / 2
    }

    private static func isSimple(_ coordinates: [OfflineGeoCoordinate]) -> Bool {
        let points = CoverageGeometry.unwrap(coordinates)
        let edgeCount = points.count - 1
        guard edgeCount >= 3 else { return false }
        for firstIndex in 0 ..< edgeCount {
            for secondIndex in (firstIndex + 1) ..< edgeCount {
                let adjacent = secondIndex == firstIndex + 1 ||
                    (firstIndex == 0 && secondIndex == edgeCount - 1)
                if adjacent { continue }
                if CoverageGeometry.segmentsIntersect(
                    points[firstIndex], points[firstIndex + 1],
                    points[secondIndex], points[secondIndex + 1],
                    includeEndpoints: true
                ) {
                    return false
                }
            }
        }
        return true
    }
}

struct OfflineCoveragePolygon: Hashable, Codable, Sendable {
    let exterior: OfflineCoverageLinearRing
    let holes: [OfflineCoverageLinearRing]

    init(exterior: OfflineCoverageLinearRing, holes: [OfflineCoverageLinearRing] = []) throws {
        guard holes.count <= OfflineCoverageLimits.maximumRingsPerPolygon else {
            throw SignedInstalledCoverageError.invalidGeometry(
                "A coverage polygon contains too many holes."
            )
        }
        for hole in holes {
            guard let sample = hole.coordinates.first,
                  CoverageGeometry.pointDisposition(sample, in: exterior) == .inside else {
                throw SignedInstalledCoverageError.invalidGeometry(
                    "Every coverage hole must be strictly inside its exterior ring."
                )
            }
            guard !CoverageGeometry.ringsIntersect(exterior, hole) else {
                throw SignedInstalledCoverageError.invalidGeometry(
                    "A coverage hole cannot intersect its exterior ring."
                )
            }
        }
        for firstIndex in holes.indices {
            for secondIndex in holes.indices where secondIndex > firstIndex {
                guard !CoverageGeometry.ringsIntersect(holes[firstIndex], holes[secondIndex]),
                      CoverageGeometry.pointDisposition(
                        holes[firstIndex].coordinates[0], in: holes[secondIndex]
                      ) == .outside,
                      CoverageGeometry.pointDisposition(
                        holes[secondIndex].coordinates[0], in: holes[firstIndex]
                      ) == .outside else {
                    throw SignedInstalledCoverageError.invalidGeometry(
                        "Coverage holes must be disjoint."
                    )
                }
            }
        }
        self.exterior = exterior
        self.holes = holes
    }

    private enum CodingKeys: String, CodingKey { case exterior, holes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                exterior: container.decode(OfflineCoverageLinearRing.self, forKey: .exterior),
                holes: container.decode([OfflineCoverageLinearRing].self, forKey: .holes)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .exterior,
                in: container,
                debugDescription: "Coverage polygon geometry is invalid."
            )
        }
    }
}

struct OfflineCoverageMultiPolygon: Hashable, Codable, Sendable {
    let polygons: [OfflineCoveragePolygon]

    init(polygons: [OfflineCoveragePolygon]) throws {
        guard !polygons.isEmpty,
              polygons.count <= OfflineCoverageLimits.maximumPolygonsPerRegion else {
            throw SignedInstalledCoverageError.invalidGeometry(
                "A coverage region must contain a bounded, non-empty multipolygon."
            )
        }
        self.polygons = polygons
    }

    private enum CodingKeys: String, CodingKey { case polygons }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(polygons: container.decode([OfflineCoveragePolygon].self, forKey: .polygons))
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .polygons,
                in: container,
                debugDescription: "Coverage multipolygon geometry is invalid."
            )
        }
    }
}

enum OfflineCoverageRegionStatus: String, Codable, Sendable {
    case active
    case revoked
}

struct HEREOfflineSignedRegion: Hashable, Codable, Sendable {
    let regionID: OfflineMapRegionID
    let catalogVersion: HEREOfflineCatalogVersion
    let status: OfflineCoverageRegionStatus
    let validFrom: Date
    let validUntil: Date
    let rightsID: String
    let boundary: OfflineCoverageMultiPolygon

    init(
        regionID: OfflineMapRegionID,
        catalogVersion: HEREOfflineCatalogVersion,
        status: OfflineCoverageRegionStatus,
        validFrom: Date,
        validUntil: Date,
        rightsID: String,
        boundary: OfflineCoverageMultiPolygon
    ) throws {
        let rightsID = rightsID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rightsID.isEmpty, rightsID.utf8.count <= OfflineCoverageLimits.identifierBytes else {
            throw SignedInstalledCoverageError.invalidManifest(
                "A coverage region source-rights identifier is invalid."
            )
        }
        guard validFrom.timeIntervalSince1970.isFinite,
              validUntil.timeIntervalSince1970.isFinite,
              validUntil > validFrom else {
            throw SignedInstalledCoverageError.invalidManifest(
                "A coverage region validity window is invalid."
            )
        }
        self.regionID = regionID
        self.catalogVersion = catalogVersion
        self.status = status
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.rightsID = rightsID
        self.boundary = boundary
    }

    private enum CodingKeys: String, CodingKey {
        case regionID, catalogVersion, status, validFrom, validUntil, rightsID, boundary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                regionID: container.decode(OfflineMapRegionID.self, forKey: .regionID),
                catalogVersion: container.decode(HEREOfflineCatalogVersion.self, forKey: .catalogVersion),
                status: container.decode(OfflineCoverageRegionStatus.self, forKey: .status),
                validFrom: container.decode(Date.self, forKey: .validFrom),
                validUntil: container.decode(Date.self, forKey: .validUntil),
                rightsID: container.decode(String.self, forKey: .rightsID),
                boundary: container.decode(OfflineCoverageMultiPolygon.self, forKey: .boundary)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .regionID,
                in: container,
                debugDescription: "Signed HERE region coverage is invalid."
            )
        }
    }
}

struct HEREOfflineSignedCoverageManifest: Hashable, Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let issuer: String
    let audience: String
    let manifestID: String
    let sequence: UInt64
    let issuedAt: Date
    let validFrom: Date
    let validUntil: Date
    let catalogVersion: HEREOfflineCatalogVersion
    let source: HEREOfflineCoverageSource
    let regions: [HEREOfflineSignedRegion]

    init(
        issuer: String,
        audience: String,
        manifestID: String,
        sequence: UInt64,
        issuedAt: Date,
        validFrom: Date,
        validUntil: Date,
        catalogVersion: HEREOfflineCatalogVersion,
        source: HEREOfflineCoverageSource,
        regions: [HEREOfflineSignedRegion]
    ) throws {
        let issuer = try Self.identifier(issuer, field: "coverage issuer")
        let audience = try Self.identifier(audience, field: "coverage audience")
        let manifestID = try Self.identifier(manifestID, field: "coverage manifest")
        guard sequence > 0 else {
            throw SignedInstalledCoverageError.invalidManifest(
                "A coverage manifest sequence must be positive."
            )
        }
        guard issuedAt.timeIntervalSince1970.isFinite,
              validFrom.timeIntervalSince1970.isFinite,
              validUntil.timeIntervalSince1970.isFinite,
              validUntil > validFrom,
              issuedAt <= validUntil else {
            throw SignedInstalledCoverageError.invalidManifest(
                "The coverage manifest validity timeline is invalid."
            )
        }
        guard !regions.isEmpty, regions.count <= OfflineCoverageLimits.maximumRegions else {
            throw SignedInstalledCoverageError.invalidManifest(
                "A coverage manifest must contain a bounded, non-empty region set."
            )
        }
        guard Set(regions.map(\.regionID)).count == regions.count else {
            throw SignedInstalledCoverageError.invalidManifest(
                "A coverage manifest cannot repeat a HERE region identifier."
            )
        }
        guard regions.allSatisfy({
            $0.catalogVersion == catalogVersion &&
                $0.rightsID == source.rightsID &&
                $0.validFrom >= validFrom &&
                $0.validUntil <= validUntil &&
                $0.validFrom >= source.rightsValidFrom &&
                $0.validUntil <= source.rightsValidUntil
        }) else {
            throw SignedInstalledCoverageError.invalidManifest(
                "Every region must match the signed catalog, rights, and validity envelope."
            )
        }
        let coordinateCount = regions.reduce(into: 0) { total, region in
            for polygon in region.boundary.polygons {
                total += polygon.exterior.coordinates.count
                for hole in polygon.holes { total += hole.coordinates.count }
            }
        }
        guard coordinateCount <= OfflineCoverageLimits.maximumCoordinatesPerManifest else {
            throw SignedInstalledCoverageError.invalidManifest(
                "The coverage manifest exceeds the safe geometry limit."
            )
        }
        self.schemaVersion = Self.currentSchemaVersion
        self.issuer = issuer
        self.audience = audience
        self.manifestID = manifestID
        self.sequence = sequence
        self.issuedAt = issuedAt
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.catalogVersion = catalogVersion
        self.source = source
        self.regions = regions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, issuer, audience, manifestID, sequence, issuedAt, validFrom, validUntil
        case catalogVersion, source, regions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported installed-coverage manifest schema."
            )
        }
        do {
            try self.init(
                issuer: container.decode(String.self, forKey: .issuer),
                audience: container.decode(String.self, forKey: .audience),
                manifestID: container.decode(String.self, forKey: .manifestID),
                sequence: container.decode(UInt64.self, forKey: .sequence),
                issuedAt: container.decode(Date.self, forKey: .issuedAt),
                validFrom: container.decode(Date.self, forKey: .validFrom),
                validUntil: container.decode(Date.self, forKey: .validUntil),
                catalogVersion: container.decode(HEREOfflineCatalogVersion.self, forKey: .catalogVersion),
                source: container.decode(HEREOfflineCoverageSource.self, forKey: .source),
                regions: container.decode([HEREOfflineSignedRegion].self, forKey: .regions)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .regions,
                in: container,
                debugDescription: "The installed-coverage manifest failed validation."
            )
        }
    }

    private static func identifier(_ rawValue: String, field: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= OfflineCoverageLimits.identifierBytes else {
            throw SignedInstalledCoverageError.invalidManifest("The \(field) claim is invalid.")
        }
        return value
    }
}

struct HEREOfflineVerifiedCoverageManifest: Hashable, Sendable {
    let signedEnvelope: OfflineCoverageSignedEnvelope
    let payload: HEREOfflineSignedCoverageManifest
}

struct HEREOfflineCoverageManifestVerifier: Sendable {
    private let expectedIssuer: String
    private let expectedAudience: String
    private let expectedSDKVersion: String
    private let expectedRightsHolder: String
    private let maximumManifestAge: TimeInterval
    private let allowedClockSkew: TimeInterval
    private let keysByID: [String: Data]

    init(
        expectedIssuer: String,
        expectedAudience: String,
        expectedSDKVersion: String,
        expectedRightsHolder: String,
        keys: [OfflineCoverageVerificationKey],
        maximumManifestAge: TimeInterval = 35 * 24 * 60 * 60,
        allowedClockSkew: TimeInterval = 300
    ) throws {
        let issuer = expectedIssuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let audience = expectedAudience.trimmingCharacters(in: .whitespacesAndNewlines)
        let sdkVersion = expectedSDKVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightsHolder = expectedRightsHolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !issuer.isEmpty, !audience.isEmpty, !sdkVersion.isEmpty, !rightsHolder.isEmpty else {
            throw SignedInstalledCoverageError.invalidPolicy(
                "Coverage issuer, audience, SDK version, and rights holder must be pinned."
            )
        }
        guard maximumManifestAge.isFinite, maximumManifestAge > 0,
              allowedClockSkew.isFinite, allowedClockSkew >= 0 else {
            throw SignedInstalledCoverageError.invalidPolicy(
                "Coverage freshness policy is invalid."
            )
        }
        let pairs = keys.map { ($0.keyID, $0.ed25519RawRepresentation) }
        guard !pairs.isEmpty, Set(pairs.map(\.0)).count == pairs.count else {
            throw SignedInstalledCoverageError.invalidPolicy(
                "Coverage verification keys must be non-empty and unique."
            )
        }
        self.expectedIssuer = issuer
        self.expectedAudience = audience
        self.expectedSDKVersion = sdkVersion
        self.expectedRightsHolder = rightsHolder
        self.maximumManifestAge = maximumManifestAge
        self.allowedClockSkew = allowedClockSkew
        keysByID = Dictionary(uniqueKeysWithValues: pairs)
    }

    func verify(
        _ envelope: OfflineCoverageSignedEnvelope,
        at trustedTime: Date
    ) throws -> HEREOfflineVerifiedCoverageManifest {
        guard trustedTime.timeIntervalSince1970.isFinite else {
            throw SignedInstalledCoverageError.trustedTimeUnavailable
        }
        let verified = try verifyPinnedClaims(envelope)
        let payload = verified.payload
        try validateCurrentValidity(of: payload, at: trustedTime)
        return verified
    }

    /// Used only to compare an already-persisted signed sequence while
    /// accepting a replacement. An expired predecessor must not prevent a
    /// newer manifest from being installed, but its signature and pinned
    /// source claims are still reverified before its sequence is trusted.
    func verifyPersistedForReplay(
        _ envelope: OfflineCoverageSignedEnvelope
    ) throws -> HEREOfflineVerifiedCoverageManifest {
        try verifyPinnedClaims(envelope)
    }

    private func verifyPinnedClaims(
        _ envelope: OfflineCoverageSignedEnvelope
    ) throws -> HEREOfflineVerifiedCoverageManifest {
        guard envelope.algorithm == .ed25519,
              let rawKey = keysByID[envelope.keyID],
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else {
            throw SignedInstalledCoverageError.untrustedSigningKey
        }
        guard publicKey.isValidSignature(envelope.signature, for: envelope.payload) else {
            throw SignedInstalledCoverageError.invalidSignature
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: HEREOfflineSignedCoverageManifest
        do {
            payload = try decoder.decode(HEREOfflineSignedCoverageManifest.self, from: envelope.payload)
        } catch {
            throw SignedInstalledCoverageError.decodingFailed
        }
        guard payload.issuer == expectedIssuer,
              payload.audience == expectedAudience,
              payload.source.vendor == .here,
              payload.source.product == .hereSDKNavigate,
              payload.source.sdkVersion == expectedSDKVersion,
              payload.source.rightsHolder == expectedRightsHolder else {
            throw SignedInstalledCoverageError.signedClaimMismatch
        }
        return HEREOfflineVerifiedCoverageManifest(signedEnvelope: envelope, payload: payload)
    }

    private func validateCurrentValidity(
        of payload: HEREOfflineSignedCoverageManifest,
        at trustedTime: Date
    ) throws {
        let earliestAcceptedTime = trustedTime.addingTimeInterval(allowedClockSkew)
        guard payload.issuedAt <= earliestAcceptedTime,
              payload.validFrom <= earliestAcceptedTime,
              payload.source.rightsValidFrom <= earliestAcceptedTime else {
            throw SignedInstalledCoverageError.notYetValid
        }
        let latestAcceptedTime = trustedTime.addingTimeInterval(-allowedClockSkew)
        guard payload.validUntil >= latestAcceptedTime else {
            throw SignedInstalledCoverageError.expiredManifest
        }
        guard payload.source.rightsValidUntil >= latestAcceptedTime else {
            throw SignedInstalledCoverageError.sourceRightsExpired
        }
        guard trustedTime.timeIntervalSince(payload.issuedAt) <= maximumManifestAge + allowedClockSkew else {
            throw SignedInstalledCoverageError.staleManifest
        }
    }
}

enum HEREInstalledRegionInventoryProvenance: String, Codable, Sendable {
    case hereSDKInstalledRegions
}

/// This snapshot must be built by the native HERE `MapDownloader` adapter.
/// Search requests, route responses, and users never supply it.
struct HEREInstalledRegionInventory: Hashable, Sendable {
    let catalogVersion: HEREOfflineCatalogVersion
    let usableRegionIDs: Set<OfflineMapRegionID>
    let observedAt: Date
    let provenance: HEREInstalledRegionInventoryProvenance

    init(
        catalogVersion: HEREOfflineCatalogVersion,
        usableRegionIDs: Set<OfflineMapRegionID>,
        observedAt: Date,
        provenance: HEREInstalledRegionInventoryProvenance = .hereSDKInstalledRegions
    ) throws {
        guard observedAt.timeIntervalSince1970.isFinite else {
            throw SignedInstalledCoverageError.invalidInventory(
                "The HERE installed-region observation time is invalid."
            )
        }
        self.catalogVersion = catalogVersion
        self.usableRegionIDs = usableRegionIDs
        self.observedAt = observedAt
        self.provenance = provenance
    }
}

protocol HEREInstalledRegionInventoryProviding: Sendable {
    func currentHEREInstalledRegionInventory() async throws -> HEREInstalledRegionInventory
}

struct AnyHEREInstalledRegionInventoryProvider: HEREInstalledRegionInventoryProviding, Sendable {
    private let provider: @Sendable () async throws -> HEREInstalledRegionInventory

    init(_ provider: @escaping @Sendable () async throws -> HEREInstalledRegionInventory) {
        self.provider = provider
    }

    func currentHEREInstalledRegionInventory() async throws -> HEREInstalledRegionInventory {
        try await provider()
    }
}

enum OfflineCoverageGeometryKind: String, Sendable {
    case point
    case searchArea
    case routeCorridor
    case gnssSample
}

/// Geometry requiring installed coverage. A search area is a closed polygon;
/// a route corridor is a polyline plus a requested half-width. Both are
/// conservatively accepted only when one signed installed HERE region covers
/// the complete geometry, never merely its bounding box.
struct OfflineCoverageRequestGeometry: Hashable, Sendable {
    let kind: OfflineCoverageGeometryKind
    let coordinates: [OfflineGeoCoordinate]
    let corridorHalfWidthMeters: Double

    static func point(_ coordinate: OfflineGeoCoordinate) -> Self {
        Self(kind: .point, coordinates: [coordinate], corridorHalfWidthMeters: 0)
    }

    static func gnssSample(_ coordinate: OfflineGeoCoordinate) -> Self {
        Self(kind: .gnssSample, coordinates: [coordinate], corridorHalfWidthMeters: 0)
    }

    static func searchArea(boundary: [OfflineGeoCoordinate]) throws -> Self {
        guard boundary.count >= 4,
              boundary.count <= OfflineCoverageLimits.maximumRequestCoordinates,
              boundary.first == boundary.last else {
            throw SignedInstalledCoverageError.invalidRequestGeometry(
                "A search area must be a closed polygon with at least three vertices."
            )
        }
        _ = try OfflineCoverageLinearRing(coordinates: boundary)
        return Self(kind: .searchArea, coordinates: boundary, corridorHalfWidthMeters: 0)
    }

    static func routeCorridor(
        coordinates: [OfflineGeoCoordinate],
        halfWidthMeters: Double = 0
    ) throws -> Self {
        guard coordinates.count >= 2,
              coordinates.count <= OfflineCoverageLimits.maximumRequestCoordinates,
              halfWidthMeters.isFinite,
              halfWidthMeters >= 0 else {
            throw SignedInstalledCoverageError.invalidRequestGeometry(
                "A route corridor needs bounded geometry and a non-negative half-width."
            )
        }
        return Self(
            kind: .routeCorridor,
            coordinates: coordinates,
            corridorHalfWidthMeters: halfWidthMeters
        )
    }

    private init(
        kind: OfflineCoverageGeometryKind,
        coordinates: [OfflineGeoCoordinate],
        corridorHalfWidthMeters: Double
    ) {
        self.kind = kind
        self.coordinates = coordinates
        self.corridorHalfWidthMeters = corridorHalfWidthMeters
    }
}

enum OfflineInstalledCoverageClassification: Equatable, Sendable {
    case verifiedInside(OfflineInstalledCoverageEvidence)
    case approachingBoundary(
        coverage: OfflineInstalledCoverageEvidence,
        distanceMeters: Int64
    )
    case outside

    var evidence: OfflineInstalledCoverageEvidence? {
        switch self {
        case .verifiedInside(let evidence): return evidence
        case .approachingBoundary(let evidence, _): return evidence
        case .outside: return nil
        }
    }
}

struct OfflineInstalledCoverageResolution: Equatable, Sendable {
    let geometryKind: OfflineCoverageGeometryKind
    let classification: OfflineInstalledCoverageClassification
    /// One signed/native-inventory classification for every exact coordinate
    /// supplied by the caller, in the same order. Aggregate geometry evidence
    /// above remains empty unless the complete area or corridor is covered.
    let coordinateClassifications: [OfflineCoverageCoordinateClassification]
    let manifestID: String
    let manifestSequence: UInt64
    let catalogVersion: HEREOfflineCatalogVersion
    let evaluatedAt: Date
}

struct OfflineCoverageCoordinateClassification: Equatable, Sendable {
    let index: Int
    let coordinate: OfflineGeoCoordinate
    let classification: OfflineInstalledCoverageClassification
}

protocol OfflineInstalledCoverageResolving: Sendable {
    func resolveInstalledCoverage(
        for geometry: OfflineCoverageRequestGeometry
    ) async throws -> OfflineInstalledCoverageResolution
}

enum SignedInstalledCoverageError: Error, Equatable, Sendable {
    case invalidPolicy(String)
    case invalidEnvelope(String)
    case invalidManifest(String)
    case invalidGeometry(String)
    case invalidRequestGeometry(String)
    case invalidInventory(String)
    case untrustedSigningKey
    case invalidSignature
    case decodingFailed
    case signedClaimMismatch
    case notYetValid
    case expiredManifest
    case sourceRightsExpired
    case staleManifest
    case revokedRegion(OfflineMapRegionID)
    case catalogMismatch(expected: HEREOfflineCatalogVersion, actual: HEREOfflineCatalogVersion)
    case inventoryTooOld
    case manifestMissing
    case replayRejected
    case clockRollbackDetected
    case trustedTimeUnavailable
    case persistenceCorrupt
    case persistenceFailed(String)
}

extension SignedInstalledCoverageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidPolicy(let message), .invalidEnvelope(let message),
             .invalidManifest(let message), .invalidGeometry(let message),
             .invalidRequestGeometry(let message), .invalidInventory(let message),
             .persistenceFailed(let message):
            return message
        case .untrustedSigningKey:
            return "The installed-coverage manifest uses an untrusted signing key."
        case .invalidSignature:
            return "The installed-coverage manifest signature is invalid."
        case .decodingFailed, .persistenceCorrupt:
            return "The installed-coverage manifest is unreadable or corrupt."
        case .signedClaimMismatch:
            return "The installed-coverage manifest claims do not match this app and HERE SDK release."
        case .notYetValid:
            return "The installed-coverage manifest is not yet valid."
        case .expiredManifest:
            return "The installed-coverage manifest has expired."
        case .sourceRightsExpired:
            return "The signed HERE source rights have expired."
        case .staleManifest:
            return "The installed-coverage manifest is too old to trust."
        case .revokedRegion:
            return "The requested HERE region coverage has been revoked."
        case .catalogMismatch:
            return "The signed coverage catalog does not match the installed HERE catalog."
        case .inventoryTooOld:
            return "The HERE installed-region inventory is stale."
        case .manifestMissing:
            return "No signed installed-region coverage manifest is available."
        case .replayRejected:
            return "An older or conflicting installed-coverage manifest was rejected."
        case .clockRollbackDetected:
            return "The device clock moved behind the accepted coverage evidence."
        case .trustedTimeUnavailable:
            return "Trusted time is unavailable for installed-coverage validation."
        }
    }
}

private final class SignedCoverageRootLeaseRegistry: @unchecked Sendable {
    static let shared = SignedCoverageRootLeaseRegistry()

    private let lock = NSLock()
    private var roots: Set<String> = []

    func acquire(_ root: URL) throws -> SignedCoverageRootLease {
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path
        lock.lock()
        defer { lock.unlock() }
        guard roots.insert(key).inserted else {
            throw SignedInstalledCoverageError.invalidPolicy(
                "Only one installed-coverage resolver may own a persistence root."
            )
        }
        return SignedCoverageRootLease(key: key)
    }

    fileprivate func release(_ key: String) {
        lock.lock()
        roots.remove(key)
        lock.unlock()
    }
}

private final class SignedCoverageRootLease: @unchecked Sendable {
    private let key: String

    fileprivate init(key: String) { self.key = key }

    deinit { SignedCoverageRootLeaseRegistry.shared.release(key) }
}

actor SignedInstalledCoverageResolver: OfflineInstalledCoverageResolving {
    private struct StoredManifest: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let envelope: OfflineCoverageSignedEnvelope
        let acceptedAt: Date

        init(envelope: OfflineCoverageSignedEnvelope, acceptedAt: Date) {
            schemaVersion = Self.currentSchemaVersion
            self.envelope = envelope
            self.acceptedAt = acceptedAt
        }

        private enum CodingKeys: String, CodingKey { case schemaVersion, envelope, acceptedAt }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == Self.currentSchemaVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported stored coverage-manifest schema."
                )
            }
            envelope = try container.decode(OfflineCoverageSignedEnvelope.self, forKey: .envelope)
            acceptedAt = try container.decode(Date.self, forKey: .acceptedAt)
            guard acceptedAt.timeIntervalSince1970.isFinite else {
                throw DecodingError.dataCorruptedError(
                    forKey: .acceptedAt,
                    in: container,
                    debugDescription: "Stored coverage acceptance time is invalid."
                )
            }
        }
    }

    private let rootDirectory: URL
    private let rootLease: SignedCoverageRootLease
    private let verifier: HEREOfflineCoverageManifestVerifier
    private let inventoryProvider: any HEREInstalledRegionInventoryProviding
    private let fileManager: FileManager
    private let boundaryWarningMeters: Double
    private let maximumInventoryAge: TimeInterval
    private let allowedClockSkew: TimeInterval
    private let currentTime: @Sendable () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        rootDirectory: URL,
        verifier: HEREOfflineCoverageManifestVerifier,
        inventoryProvider: any HEREInstalledRegionInventoryProviding,
        boundaryWarningMeters: Double = 5_000,
        maximumInventoryAge: TimeInterval = 15 * 60,
        allowedClockSkew: TimeInterval = 300,
        fileManager: FileManager = .default,
        currentTime: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        guard boundaryWarningMeters.isFinite, boundaryWarningMeters >= 0,
              maximumInventoryAge.isFinite, maximumInventoryAge > 0,
              allowedClockSkew.isFinite, allowedClockSkew >= 0 else {
            throw SignedInstalledCoverageError.invalidPolicy(
                "Installed-coverage boundary and freshness policy is invalid."
            )
        }
        let root = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        rootLease = try SignedCoverageRootLeaseRegistry.shared.acquire(root)
        self.rootDirectory = root
        self.verifier = verifier
        self.inventoryProvider = inventoryProvider
        self.boundaryWarningMeters = boundaryWarningMeters
        self.maximumInventoryAge = maximumInventoryAge
        self.allowedClockSkew = allowedClockSkew
        self.fileManager = fileManager
        self.currentTime = currentTime
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    func installSignedManifest(
        _ envelope: OfflineCoverageSignedEnvelope,
        acceptedAt: Date? = nil
    ) throws -> HEREOfflineVerifiedCoverageManifest {
        let now = try trustworthyNow(acceptedAt ?? currentTime())
        let candidate = try verifier.verify(envelope, at: now)
        if let existing = try readStoredManifest(at: now, requireCurrentValidity: false) {
            if candidate.payload.sequence < existing.verified.payload.sequence ||
                candidate.payload.issuedAt < existing.verified.payload.issuedAt {
                throw SignedInstalledCoverageError.replayRejected
            }
            if candidate.payload.sequence == existing.verified.payload.sequence {
                guard candidate.signedEnvelope == existing.verified.signedEnvelope else {
                    throw SignedInstalledCoverageError.replayRejected
                }
                return existing.verified
            }
        }
        try write(StoredManifest(envelope: envelope, acceptedAt: now))
        return candidate
    }

    func removeSignedManifest() throws {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        do {
            try fileManager.removeItem(at: manifestURL)
        } catch {
            throw SignedInstalledCoverageError.persistenceFailed(
                "The signed installed-coverage manifest could not be removed."
            )
        }
    }

    func resolveInstalledCoverage(
        for geometry: OfflineCoverageRequestGeometry
    ) async throws -> OfflineInstalledCoverageResolution {
        let now = try trustworthyNow(currentTime())
        guard let stored = try readStoredManifest(at: now, requireCurrentValidity: true) else {
            throw SignedInstalledCoverageError.manifestMissing
        }
        guard now.addingTimeInterval(allowedClockSkew) >= stored.stored.acceptedAt else {
            throw SignedInstalledCoverageError.clockRollbackDetected
        }

        let inventory: HEREInstalledRegionInventory
        do {
            inventory = try await inventoryProvider.currentHEREInstalledRegionInventory()
        } catch let error as SignedInstalledCoverageError {
            throw error
        } catch {
            throw SignedInstalledCoverageError.invalidInventory(
                "The native HERE installed-region inventory is unavailable."
            )
        }
        guard inventory.provenance == .hereSDKInstalledRegions else {
            throw SignedInstalledCoverageError.invalidInventory(
                "Installed-region inventory does not have native HERE provenance."
            )
        }
        guard inventory.catalogVersion == stored.verified.payload.catalogVersion else {
            throw SignedInstalledCoverageError.catalogMismatch(
                expected: stored.verified.payload.catalogVersion,
                actual: inventory.catalogVersion
            )
        }
        guard inventory.observedAt <= now.addingTimeInterval(allowedClockSkew),
              now.timeIntervalSince(inventory.observedAt) <= maximumInventoryAge + allowedClockSkew else {
            throw SignedInstalledCoverageError.inventoryTooOld
        }

        let eligible = stored.verified.payload.regions.filter { region in
            region.status == .active &&
                inventory.usableRegionIDs.contains(region.regionID) &&
                now.addingTimeInterval(allowedClockSkew) >= region.validFrom &&
                now.addingTimeInterval(-allowedClockSkew) <= region.validUntil
        }
        var covering: [(region: HEREOfflineSignedRegion, boundaryDistance: Double)] = []
        for region in eligible {
            if let distance = CoverageGeometry.minimumSafeBoundaryDistance(
                for: geometry,
                within: region.boundary
            ) {
                covering.append((region, distance))
            }
        }

        let coordinateClassifications = try geometry.coordinates.enumerated().map { index, coordinate in
            var pointCovering: [(region: HEREOfflineSignedRegion, boundaryDistance: Double)] = []
            let pointRequest = OfflineCoverageRequestGeometry.point(coordinate)
            for region in eligible {
                if let distance = CoverageGeometry.minimumSafeBoundaryDistance(
                    for: pointRequest,
                    within: region.boundary
                ) {
                    pointCovering.append((region, distance))
                }
            }
            let pointClassification: OfflineInstalledCoverageClassification
            if pointCovering.isEmpty {
                pointClassification = .outside
            } else {
                let pointIDs = pointCovering.map(\.region.regionID).sorted {
                    $0.rawValue < $1.rawValue
                }
                let pointEvidence = try OfflineInstalledCoverageEvidence(regionIDs: pointIDs)
                let pointDistance = pointCovering.map(\.boundaryDistance).max() ?? 0
                if pointDistance <= boundaryWarningMeters {
                    pointClassification = .approachingBoundary(
                        coverage: pointEvidence,
                        distanceMeters: Int64(max(0, pointDistance).rounded(.down))
                    )
                } else {
                    pointClassification = .verifiedInside(pointEvidence)
                }
            }
            return OfflineCoverageCoordinateClassification(
                index: index,
                coordinate: coordinate,
                classification: pointClassification
            )
        }

        let classification: OfflineInstalledCoverageClassification
        if covering.isEmpty {
            if let revokedCovering = stored.verified.payload.regions.first(where: { region in
                region.status == .revoked &&
                    inventory.usableRegionIDs.contains(region.regionID) &&
                    CoverageGeometry.minimumSafeBoundaryDistance(
                        for: geometry,
                        within: region.boundary
                    ) != nil
            }) {
                throw SignedInstalledCoverageError.revokedRegion(revokedCovering.regionID)
            }
            classification = .outside
        } else {
            let sortedIDs = covering.map(\.region.regionID).sorted { $0.rawValue < $1.rawValue }
            let evidence = try OfflineInstalledCoverageEvidence(regionIDs: sortedIDs)
            let safestDistance = covering.map(\.boundaryDistance).max() ?? 0
            if safestDistance <= boundaryWarningMeters {
                classification = .approachingBoundary(
                    coverage: evidence,
                    distanceMeters: Int64(max(0, safestDistance).rounded(.down))
                )
            } else {
                classification = .verifiedInside(evidence)
            }
        }
        return OfflineInstalledCoverageResolution(
            geometryKind: geometry.kind,
            classification: classification,
            coordinateClassifications: coordinateClassifications,
            manifestID: stored.verified.payload.manifestID,
            manifestSequence: stored.verified.payload.sequence,
            catalogVersion: stored.verified.payload.catalogVersion,
            evaluatedAt: now
        )
    }

    private struct StoredVerifiedManifest {
        let stored: StoredManifest
        let verified: HEREOfflineVerifiedCoverageManifest
    }

    private func readStoredManifest(
        at now: Date,
        requireCurrentValidity: Bool
    ) throws -> StoredVerifiedManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: manifestURL.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.intValue <= OfflineCoverageLimits.persistedEnvelopeBytes else {
                throw SignedInstalledCoverageError.persistenceCorrupt
            }
            let data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
            let stored = try decoder.decode(StoredManifest.self, from: data)
            guard now.addingTimeInterval(allowedClockSkew) >= stored.acceptedAt else {
                throw SignedInstalledCoverageError.clockRollbackDetected
            }
            let verified = try requireCurrentValidity
                ? verifier.verify(stored.envelope, at: now)
                : verifier.verifyPersistedForReplay(stored.envelope)
            return StoredVerifiedManifest(stored: stored, verified: verified)
        } catch let error as SignedInstalledCoverageError {
            throw error
        } catch {
            throw SignedInstalledCoverageError.persistenceCorrupt
        }
    }

    private func write(_ stored: StoredManifest) throws {
        do {
            try fileManager.createDirectory(at: coverageDirectory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = coverageDirectory
            try mutableDirectory.setResourceValues(values)
#if os(iOS) || os(tvOS) || os(watchOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: coverageDirectory.path
            )
#endif
            let data = try encoder.encode(stored)
            guard data.count <= OfflineCoverageLimits.persistedEnvelopeBytes else {
                throw SignedInstalledCoverageError.invalidEnvelope(
                    "The persisted coverage envelope exceeds the safe byte limit."
                )
            }
            try data.write(to: manifestURL, options: .atomic)
#if os(iOS) || os(tvOS) || os(watchOS)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: manifestURL.path
            )
#endif
        } catch let error as SignedInstalledCoverageError {
            throw error
        } catch {
            throw SignedInstalledCoverageError.persistenceFailed(
                "The signed installed-coverage manifest could not be written atomically."
            )
        }
    }

    private func trustworthyNow(_ value: Date) throws -> Date {
        guard value.timeIntervalSince1970.isFinite else {
            throw SignedInstalledCoverageError.trustedTimeUnavailable
        }
        return value
    }

    private var coverageDirectory: URL {
        rootDirectory.appendingPathComponent("here-installed-coverage", isDirectory: true)
    }

    private var manifestURL: URL {
        coverageDirectory.appendingPathComponent("v1-signed-manifest.json", isDirectory: false)
    }
}

private enum CoveragePointDisposition {
    case outside
    case boundary
    case inside
}

private enum CoverageGeometry {
    struct Point {
        let x: Double
        let y: Double
    }

    static func unwrap(_ coordinates: [OfflineGeoCoordinate]) -> [Point] {
        guard let first = coordinates.first else { return [] }
        var result = [Point(x: first.longitude, y: first.latitude)]
        result.reserveCapacity(coordinates.count)
        var priorLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            let longitude = priorLongitude + normalizedLongitudeDelta(coordinate.longitude - priorLongitude)
            result.append(Point(x: longitude, y: coordinate.latitude))
            priorLongitude = longitude
        }
        return result
    }

    static func pointDisposition(
        _ coordinate: OfflineGeoCoordinate,
        in ring: OfflineCoverageLinearRing
    ) -> CoveragePointDisposition {
        let points = unwrap(ring.coordinates)
        guard !points.isEmpty else { return .outside }
        let averageLongitude = points.reduce(0) { $0 + $1.x } / Double(points.count)
        let queryLongitude = coordinate.longitude +
            (360 * ((averageLongitude - coordinate.longitude) / 360).rounded())
        let query = Point(x: queryLongitude, y: coordinate.latitude)
        var inside = false
        for index in 0 ..< points.count - 1 {
            let start = points[index]
            let end = points[index + 1]
            if pointOnSegment(query, start, end) { return .boundary }
            let crosses = (start.y > query.y) != (end.y > query.y)
            if crosses {
                let crossingX = start.x + (query.y - start.y) * (end.x - start.x) / (end.y - start.y)
                if crossingX > query.x { inside.toggle() }
            }
        }
        return inside ? .inside : .outside
    }

    static func contains(_ coordinate: OfflineGeoCoordinate, in polygon: OfflineCoveragePolygon) -> Bool {
        let exterior = pointDisposition(coordinate, in: polygon.exterior)
        guard exterior != .outside else { return false }
        for hole in polygon.holes {
            let disposition = pointDisposition(coordinate, in: hole)
            if disposition == .inside { return false }
            if disposition == .boundary { return true }
        }
        return true
    }

    static func strictlyContains(_ coordinate: OfflineGeoCoordinate, in polygon: OfflineCoveragePolygon) -> Bool {
        guard pointDisposition(coordinate, in: polygon.exterior) == .inside else { return false }
        return polygon.holes.allSatisfy { pointDisposition(coordinate, in: $0) == .outside }
    }

    static func minimumSafeBoundaryDistance(
        for request: OfflineCoverageRequestGeometry,
        within multipolygon: OfflineCoverageMultiPolygon
    ) -> Double? {
        var best: Double?
        for polygon in multipolygon.polygons {
            guard geometry(request, isFullyCoveredBy: polygon) else { continue }
            let distance = minimumBoundaryDistance(for: request, in: polygon)
            if distance + OfflineCoverageLimits.geometricEpsilon < request.corridorHalfWidthMeters {
                continue
            }
            best = max(best ?? 0, max(0, distance - request.corridorHalfWidthMeters))
        }
        return best
    }

    private static func geometry(
        _ request: OfflineCoverageRequestGeometry,
        isFullyCoveredBy polygon: OfflineCoveragePolygon
    ) -> Bool {
        guard request.coordinates.allSatisfy({ contains($0, in: polygon) }) else { return false }
        switch request.kind {
        case .point, .gnssSample:
            return true
        case .routeCorridor:
            return zip(request.coordinates, request.coordinates.dropFirst()).allSatisfy {
                segmentIsCovered($0, $1, by: polygon)
            }
        case .searchArea:
            guard zip(request.coordinates, request.coordinates.dropFirst()).allSatisfy({
                segmentIsCovered($0, $1, by: polygon)
            }) else { return false }
            let requestRing: OfflineCoverageLinearRing
            do {
                requestRing = try OfflineCoverageLinearRing(coordinates: request.coordinates)
            } catch {
                return false
            }
            // A hole enclosed by the requested area makes full-area coverage
            // false even when every requested boundary coordinate is inside.
            for hole in polygon.holes {
                if hole.coordinates.dropLast().contains(where: {
                    pointDisposition($0, in: requestRing) != .outside
                }) {
                    return false
                }
            }
            // If the request encloses an exterior vertex, it reaches beyond
            // this polygon even if a concave boundary happened to avoid a
            // vertex-only check. Fail closed rather than approximate an area.
            if polygon.exterior.coordinates.dropLast().contains(where: {
                pointDisposition($0, in: requestRing) == .inside
            }) {
                return false
            }
            return true
        }
    }

    private static func segmentIsCovered(
        _ start: OfflineGeoCoordinate,
        _ end: OfflineGeoCoordinate,
        by polygon: OfflineCoveragePolygon
    ) -> Bool {
        guard contains(start, in: polygon), contains(end, in: polygon) else { return false }
        var parameters: [Double] = [0, 1]
        for ring in [polygon.exterior] + polygon.holes {
            parameters.append(contentsOf: intersectionParameters(start, end, ring: ring))
        }
        parameters = Array(Set(parameters.map { min(1, max(0, $0)) })).sorted()
        for pair in zip(parameters, parameters.dropFirst()) where pair.1 - pair.0 > 1e-12 {
            let midpoint = interpolate(start, end, parameter: (pair.0 + pair.1) / 2)
            if !contains(midpoint, in: polygon) { return false }
        }
        return true
    }

    private static func intersectionParameters(
        _ start: OfflineGeoCoordinate,
        _ end: OfflineGeoCoordinate,
        ring: OfflineCoverageLinearRing
    ) -> [Double] {
        let segmentStart = Point(x: start.longitude, y: start.latitude)
        let segmentEnd = Point(
            x: start.longitude + normalizedLongitudeDelta(end.longitude - start.longitude),
            y: end.latitude
        )
        let ringPoints = unwrap(ring.coordinates)
        guard !ringPoints.isEmpty else { return [] }
        let segmentMidpoint = (segmentStart.x + segmentEnd.x) / 2
        let ringAverage = ringPoints.reduce(0) { $0 + $1.x } / Double(ringPoints.count)
        let shift = 360 * ((segmentMidpoint - ringAverage) / 360).rounded()
        var result: [Double] = []
        for index in 0 ..< ringPoints.count - 1 {
            let edgeStart = Point(x: ringPoints[index].x + shift, y: ringPoints[index].y)
            let edgeEnd = Point(x: ringPoints[index + 1].x + shift, y: ringPoints[index + 1].y)
            if let parameter = segmentIntersectionParameter(segmentStart, segmentEnd, edgeStart, edgeEnd) {
                result.append(parameter)
            }
        }
        return result
    }

    private static func minimumBoundaryDistance(
        for request: OfflineCoverageRequestGeometry,
        in polygon: OfflineCoveragePolygon
    ) -> Double {
        let rings = [polygon.exterior] + polygon.holes
        switch request.kind {
        case .point, .gnssSample:
            return rings.map { distance(request.coordinates[0], to: $0) }.min() ?? 0
        case .searchArea, .routeCorridor:
            var minimum = Double.greatestFiniteMagnitude
            for requestSegment in zip(request.coordinates, request.coordinates.dropFirst()) {
                for ring in rings {
                    let ringCoordinates = ring.coordinates
                    for boundarySegment in zip(ringCoordinates, ringCoordinates.dropFirst()) {
                        minimum = min(
                            minimum,
                            distanceBetweenSegments(
                                requestSegment.0,
                                requestSegment.1,
                                boundarySegment.0,
                                boundarySegment.1
                            )
                        )
                    }
                }
            }
            return minimum.isFinite ? minimum : 0
        }
    }

    static func ringsIntersect(
        _ first: OfflineCoverageLinearRing,
        _ second: OfflineCoverageLinearRing
    ) -> Bool {
        for firstSegment in zip(first.coordinates, first.coordinates.dropFirst()) {
            for secondSegment in zip(second.coordinates, second.coordinates.dropFirst()) {
                if geographicSegmentsIntersect(
                    firstSegment.0, firstSegment.1,
                    secondSegment.0, secondSegment.1
                ) {
                    return true
                }
            }
        }
        return false
    }

    private static func geographicSegmentsIntersect(
        _ a: OfflineGeoCoordinate,
        _ b: OfflineGeoCoordinate,
        _ c: OfflineGeoCoordinate,
        _ d: OfflineGeoCoordinate
    ) -> Bool {
        let firstStart = Point(x: a.longitude, y: a.latitude)
        let firstEnd = Point(
            x: a.longitude + normalizedLongitudeDelta(b.longitude - a.longitude),
            y: b.latitude
        )
        let secondStartRaw = a.longitude + normalizedLongitudeDelta(c.longitude - a.longitude)
        let secondStart = Point(x: secondStartRaw, y: c.latitude)
        let secondEnd = Point(
            x: secondStartRaw + normalizedLongitudeDelta(d.longitude - c.longitude),
            y: d.latitude
        )
        return segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd, includeEndpoints: true)
    }

    static func segmentsIntersect(
        _ a: Point,
        _ b: Point,
        _ c: Point,
        _ d: Point,
        includeEndpoints: Bool
    ) -> Bool {
        let first = orientation(a, b, c)
        let second = orientation(a, b, d)
        let third = orientation(c, d, a)
        let fourth = orientation(c, d, b)
        if ((first > 0 && second < 0) || (first < 0 && second > 0)) &&
            ((third > 0 && fourth < 0) || (third < 0 && fourth > 0)) {
            return true
        }
        guard includeEndpoints else { return false }
        if abs(first) <= OfflineCoverageLimits.geometricEpsilon && pointOnSegment(c, a, b) { return true }
        if abs(second) <= OfflineCoverageLimits.geometricEpsilon && pointOnSegment(d, a, b) { return true }
        if abs(third) <= OfflineCoverageLimits.geometricEpsilon && pointOnSegment(a, c, d) { return true }
        if abs(fourth) <= OfflineCoverageLimits.geometricEpsilon && pointOnSegment(b, c, d) { return true }
        return false
    }

    private static func pointOnSegment(_ point: Point, _ start: Point, _ end: Point) -> Bool {
        guard abs(orientation(start, end, point)) <= OfflineCoverageLimits.geometricEpsilon else {
            return false
        }
        return point.x >= min(start.x, end.x) - OfflineCoverageLimits.geometricEpsilon &&
            point.x <= max(start.x, end.x) + OfflineCoverageLimits.geometricEpsilon &&
            point.y >= min(start.y, end.y) - OfflineCoverageLimits.geometricEpsilon &&
            point.y <= max(start.y, end.y) + OfflineCoverageLimits.geometricEpsilon
    }

    private static func orientation(_ a: Point, _ b: Point, _ c: Point) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func segmentIntersectionParameter(
        _ a: Point,
        _ b: Point,
        _ c: Point,
        _ d: Point
    ) -> Double? {
        let r = Point(x: b.x - a.x, y: b.y - a.y)
        let s = Point(x: d.x - c.x, y: d.y - c.y)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > OfflineCoverageLimits.geometricEpsilon else { return nil }
        let delta = Point(x: c.x - a.x, y: c.y - a.y)
        let parameter = (delta.x * s.y - delta.y * s.x) / denominator
        let edgeParameter = (delta.x * r.y - delta.y * r.x) / denominator
        guard parameter >= -OfflineCoverageLimits.geometricEpsilon,
              parameter <= 1 + OfflineCoverageLimits.geometricEpsilon,
              edgeParameter >= -OfflineCoverageLimits.geometricEpsilon,
              edgeParameter <= 1 + OfflineCoverageLimits.geometricEpsilon else { return nil }
        return parameter
    }

    private static func interpolate(
        _ start: OfflineGeoCoordinate,
        _ end: OfflineGeoCoordinate,
        parameter: Double
    ) -> OfflineGeoCoordinate {
        let longitude = start.longitude + normalizedLongitudeDelta(end.longitude - start.longitude) * parameter
        let normalizedLongitude = ((longitude + 180).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) - 180
        // Inputs and interpolation are already finite and within latitude
        // bounds. This cannot fail for a convex interpolation parameter.
        return try! OfflineGeoCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * parameter,
            longitude: normalizedLongitude
        )
    }

    private static func normalizedLongitudeDelta(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }

    private static func distance(
        _ coordinate: OfflineGeoCoordinate,
        to ring: OfflineCoverageLinearRing
    ) -> Double {
        zip(ring.coordinates, ring.coordinates.dropFirst()).map {
            distancePointToSegment(coordinate, $0, $1)
        }.min() ?? 0
    }

    private static func distanceBetweenSegments(
        _ a: OfflineGeoCoordinate,
        _ b: OfflineGeoCoordinate,
        _ c: OfflineGeoCoordinate,
        _ d: OfflineGeoCoordinate
    ) -> Double {
        if geographicSegmentsIntersect(a, b, c, d) { return 0 }
        return min(
            distancePointToSegment(a, c, d),
            distancePointToSegment(b, c, d),
            distancePointToSegment(c, a, b),
            distancePointToSegment(d, a, b)
        )
    }

    private static func distancePointToSegment(
        _ point: OfflineGeoCoordinate,
        _ start: OfflineGeoCoordinate,
        _ end: OfflineGeoCoordinate
    ) -> Double {
        let latitudeReference = point.latitude * .pi / 180
        func local(_ coordinate: OfflineGeoCoordinate) -> Point {
            Point(
                x: normalizedLongitudeDelta(coordinate.longitude - point.longitude) * .pi / 180 *
                    cos(latitudeReference) * OfflineCoverageLimits.earthRadiusMeters,
                y: (coordinate.latitude - point.latitude) * .pi / 180 * OfflineCoverageLimits.earthRadiusMeters
            )
        }
        let origin = Point(x: 0, y: 0)
        let a = local(start)
        let b = local(end)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared <= Double.ulpOfOne {
            return hypot(a.x - origin.x, a.y - origin.y)
        }
        let parameter = min(1, max(0, -(a.x * dx + a.y * dy) / lengthSquared))
        return hypot(a.x + parameter * dx, a.y + parameter * dy)
    }
}
