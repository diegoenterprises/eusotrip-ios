//
//  HereNavigateInstalledCoverageAdapter.swift
//  EusoTrip
//
//  Release-pinned trust and process-wide admission for signed HERE installed
//  region geometry. The native inventory and the signed catalog remain
//  independent authorities and must agree before local results are returned.
//

import Foundation

struct HereNavigateInstalledCoverageInstallation: Sendable {
    let resolver: any OfflineInstalledCoverageResolving
    let expectedSDKVersion: String
    let routeCorridorHalfWidthMeters: Double

    init(
        resolver: any OfflineInstalledCoverageResolving,
        expectedSDKVersion: String,
        routeCorridorHalfWidthMeters: Double
    ) throws {
        let expectedSDKVersion = expectedSDKVersion.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !expectedSDKVersion.isEmpty,
              routeCorridorHalfWidthMeters.isFinite,
              routeCorridorHalfWidthMeters > 0,
              routeCorridorHalfWidthMeters <= 5_000 else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidPolicy
        }
        self.resolver = resolver
        self.expectedSDKVersion = expectedSDKVersion
        self.routeCorridorHalfWidthMeters = routeCorridorHalfWidthMeters
    }
}

/// Synchronous installation is intentional: app composition is created before
/// its first async `prepare()`, while the HERE engine is process-global. The
/// registry is write-once so a later caller cannot replace release trust while
/// a coordinator or Navigator is suspended across an `await`.
final class HereNavigateInstalledCoverageAuthority: @unchecked Sendable {
    static let shared = HereNavigateInstalledCoverageAuthority()

    private let lock = NSLock()
    private var retainedInstallation: HereNavigateInstalledCoverageInstallation?

    init() {}

    func installOnce(_ installation: HereNavigateInstalledCoverageInstallation) throws {
        lock.lock()
        defer { lock.unlock() }
        guard retainedInstallation == nil else {
            throw HereNavigateInstalledCoverageConfigurationError.alreadyInstalled
        }
        retainedInstallation = installation
    }

    func currentInstallation() -> HereNavigateInstalledCoverageInstallation? {
        lock.lock()
        defer { lock.unlock() }
        return retainedInstallation
    }
}

enum HereNavigateCoverageAdmission {
    static func requireCompleteEvidence(
        _ resolution: OfflineInstalledCoverageResolution,
        expectedCoordinateCount: Int? = nil,
        expectedGeometryKind: OfflineCoverageGeometryKind? = nil
    ) throws -> OfflineInstalledCoverageEvidence {
        switch resolution.classification {
        case .verifiedInside(let evidence), .approachingBoundary(let evidence, _):
            let coordinateEvidence = resolution.coordinateClassifications
            let expectedIndices = Array(coordinateEvidence.indices)
            let aggregateRegionIDs = Set(evidence.regionIDs)
            guard !coordinateEvidence.isEmpty,
                  expectedCoordinateCount.map({ $0 == coordinateEvidence.count }) ?? true,
                  expectedGeometryKind.map({ $0 == resolution.geometryKind }) ?? true,
                  coordinateEvidence.map(\.index).sorted() == expectedIndices,
                  coordinateEvidence.allSatisfy({ coordinate in
                      guard let value = coordinate.classification.evidence else {
                          return false
                      }
                      return aggregateRegionIDs.isSubset(
                          of: Set(value.regionIDs)
                      )
                  }) else {
                throw coverageFailure(
                    "Signed coverage did not exactly classify the requested geometry and every coordinate."
                )
            }
            return evidence
        case .outside:
            throw coverageFailure(
                "The requested geometry is not completely covered by a signed installed HERE region."
            )
        }
    }

    static func requireCurrentRouteEvidence(
        _ resolution: OfflineInstalledCoverageResolution,
        contains expected: OfflineInstalledCoverageEvidence,
        expectedCoordinateCount: Int? = nil,
        expectedGeometryKind: OfflineCoverageGeometryKind? = nil
    ) throws -> OfflineNavigationCoverage {
        let evidence = try requireCompleteEvidence(
            resolution,
            expectedCoordinateCount: expectedCoordinateCount,
            expectedGeometryKind: expectedGeometryKind
        )
        guard Set(expected.regionIDs).isSubset(of: Set(evidence.regionIDs)) else {
            throw coverageFailure(
                "The route's installed-region evidence no longer matches current signed coverage."
            )
        }
        return navigationCoverage(from: resolution.classification)
    }

    static func navigationCoverage(
        from classification: OfflineInstalledCoverageClassification
    ) -> OfflineNavigationCoverage {
        switch classification {
        case .verifiedInside(let evidence):
            return .verified(evidence)
        case .approachingBoundary(let evidence, let distanceMeters):
            return .approachingBoundary(
                coverage: evidence,
                distanceMeters: distanceMeters
            )
        case .outside:
            return .outsideInstalledCoverage(lastCovered: nil)
        }
    }

    static func unionEvidence(
        _ values: [OfflineInstalledCoverageEvidence]
    ) throws -> OfflineInstalledCoverageEvidence {
        let unique = Set(values.flatMap(\.regionIDs))
        return try OfflineInstalledCoverageEvidence(
            regionIDs: unique.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private static func coverageFailure(
        _ message: String
    ) -> HereNavigateOfflineAdapterError {
        HereNavigateOfflineAdapterError.operation(
            .coverageUnverified,
            message,
            recovery: "Install the signed catalog matching the native HERE map version and the complete requested geometry."
        )
    }
}

struct HereNavigateInstalledCoverageTrustConfiguration: Sendable {
    static let resourceName = "HERE_INSTALLED_COVERAGE_TRUST"
    static let releaseApprovedSDKVersion = "4.27.2.0"

    let issuer: String
    let audience: String
    let expectedSDKVersion: String
    let expectedRightsHolder: String
    let verificationKey: OfflineCoverageVerificationKey
    let initialSignedManifest: OfflineCoverageSignedEnvelope
    let routeCorridorHalfWidthMeters: Double

    static func load(
        bundle: Bundle,
        currentTime: Date = Date()
    ) throws -> Self? {
        guard let configurationURL = bundle.url(
            forResource: resourceName,
            withExtension: "json"
        ) else { return nil }
        let data = try boundedData(
            at: configurationURL,
            maximumBytes: 128 * 1_024
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: Document
        do {
            document = try decoder.decode(Document.self, from: data)
        } catch {
            throw HereNavigateInstalledCoverageConfigurationError.invalidDocument
        }
        guard document.schemaVersion == 1 else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidDocument
        }
        guard document.status == .approved else { return nil }
        guard currentTime.timeIntervalSinceReferenceDate.isFinite,
              document.approvedAt.timeIntervalSinceReferenceDate.isFinite,
              document.approvedAt <= currentTime.addingTimeInterval(300),
              !normalized(document.approvedBy).isEmpty else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidApproval
        }

        let issuer = normalized(document.issuer)
        let audience = normalized(document.audience)
        let expectedSDKVersion = normalized(document.expectedSDKVersion)
        let rightsHolder = normalized(document.expectedRightsHolder)
        let keyID = normalized(document.verificationKeyID)
        guard !issuer.isEmpty,
              !audience.isEmpty,
              expectedSDKVersion == releaseApprovedSDKVersion,
              !rightsHolder.isEmpty,
              !keyID.isEmpty,
              let keyData = Data(base64Encoded: document.ed25519PublicKeyBase64),
              keyData.count == 32,
              document.routeCorridorHalfWidthMeters.isFinite,
              document.routeCorridorHalfWidthMeters > 0,
              document.routeCorridorHalfWidthMeters <= 5_000 else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidPolicy
        }

        let manifestName = normalized(document.initialSignedManifestResource)
        guard !manifestName.isEmpty,
              manifestName == (manifestName as NSString).lastPathComponent,
              !manifestName.contains(".."),
              (manifestName as NSString).pathExtension.lowercased() == "json" else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidManifestResource
        }
        let baseName = (manifestName as NSString).deletingPathExtension
        guard let manifestURL = bundle.url(
            forResource: baseName,
            withExtension: "json"
        ) else {
            throw HereNavigateInstalledCoverageConfigurationError.missingManifestResource
        }
        let manifestData = try boundedData(
            at: manifestURL,
            maximumBytes: 24 * 1_024 * 1_024
        )
        let envelope: OfflineCoverageSignedEnvelope
        do {
            envelope = try JSONDecoder().decode(
                OfflineCoverageSignedEnvelope.self,
                from: manifestData
            )
        } catch {
            throw HereNavigateInstalledCoverageConfigurationError.invalidManifestResource
        }
        guard envelope.keyID == keyID else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidManifestResource
        }

        return try Self(
            issuer: issuer,
            audience: audience,
            expectedSDKVersion: expectedSDKVersion,
            expectedRightsHolder: rightsHolder,
            verificationKey: OfflineCoverageVerificationKey(
                keyID: keyID,
                ed25519RawRepresentation: keyData
            ),
            initialSignedManifest: envelope,
            routeCorridorHalfWidthMeters: document.routeCorridorHalfWidthMeters
        )
    }

    private init(
        issuer: String,
        audience: String,
        expectedSDKVersion: String,
        expectedRightsHolder: String,
        verificationKey: OfflineCoverageVerificationKey,
        initialSignedManifest: OfflineCoverageSignedEnvelope,
        routeCorridorHalfWidthMeters: Double
    ) throws {
        guard routeCorridorHalfWidthMeters.isFinite,
              routeCorridorHalfWidthMeters > 0 else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidPolicy
        }
        self.issuer = issuer
        self.audience = audience
        self.expectedSDKVersion = expectedSDKVersion
        self.expectedRightsHolder = expectedRightsHolder
        self.verificationKey = verificationKey
        self.initialSignedManifest = initialSignedManifest
        self.routeCorridorHalfWidthMeters = routeCorridorHalfWidthMeters
    }

    private static func boundedData(
        at url: URL,
        maximumBytes: Int
    ) throws -> Data {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0,
              size <= maximumBytes else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidDocument
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw HereNavigateInstalledCoverageConfigurationError.invalidDocument
        }
        return data
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let status: Status
        let issuer: String
        let audience: String
        let expectedSDKVersion: String
        let expectedRightsHolder: String
        let verificationKeyID: String
        let ed25519PublicKeyBase64: String
        let initialSignedManifestResource: String
        let routeCorridorHalfWidthMeters: Double
        let approvedBy: String
        let approvedAt: Date
    }

    private enum Status: String, Decodable {
        case awaitingSignedCatalog = "awaiting_signed_catalog"
        case approved
    }
}

enum HereNavigateInstalledCoverageConfigurationError: Error, Equatable {
    case invalidDocument
    case invalidApproval
    case invalidPolicy
    case invalidManifestResource
    case missingManifestResource
    case alreadyInstalled
}

extension HereNavigateInstalledCoverageConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "The release-pinned HERE installed-coverage trust document is invalid."
        case .invalidApproval:
            return "HERE installed-coverage trust does not have a valid release approval."
        case .invalidPolicy:
            return "HERE installed-coverage trust does not match the approved SDK and boundary policy."
        case .invalidManifestResource:
            return "The bundled signed HERE installed-coverage manifest is invalid."
        case .missingManifestResource:
            return "The approved signed HERE installed-coverage manifest is not bundled."
        case .alreadyInstalled:
            return "HERE installed-coverage trust is already owned by another process composition."
        }
    }
}
