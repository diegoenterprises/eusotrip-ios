import CryptoKit
import Foundation
import XCTest
@testable import EusoTrip

private final class LockedCoverageTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var timeValue: Date
    private var inventoryValue: HEREInstalledRegionInventory

    init(time: Date, inventory: HEREInstalledRegionInventory) {
        timeValue = time
        inventoryValue = inventory
    }

    func time() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return timeValue
    }

    func setTime(_ value: Date) {
        lock.lock()
        timeValue = value
        lock.unlock()
    }

    func inventory() -> HEREInstalledRegionInventory {
        lock.lock()
        defer { lock.unlock() }
        return inventoryValue
    }

    func setInventory(_ value: HEREInstalledRegionInventory) {
        lock.lock()
        inventoryValue = value
        lock.unlock()
    }
}

final class SignedInstalledCoverageResolverTests: XCTestCase {
    private let issuer = "https://coverage.eusotrip.test"
    private let audience = "com.app.eusotrip"
    private let sdkVersion = "4.27.2.0"
    private let rightsHolder = "HERE Global B.V."
    private let keyID = "here-coverage-test-key"

    func testValidSignedInstalledRegionClassifiesPointWithExactAttribution() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        let envelope = try makeEnvelope(
            key: fixture.key,
            now: fixture.now,
            regions: [region]
        )

        _ = try await fixture.resolver.installSignedManifest(envelope)
        let resolution = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(5, 5))
        )

        guard case .verifiedInside(let evidence) = resolution.classification else {
            XCTFail("A signed, installed, matching region must classify as verified inside.")
            return
        }
        XCTAssertEqual(evidence.regionIDs.map(\.rawValue), ["here:region:alpha"])
        XCTAssertEqual(resolution.catalogVersion, fixture.catalog)
        XCTAssertEqual(resolution.manifestSequence, 1)
    }

    func testBadSignatureUnknownKeyAndWrongClaimsFailBeforePersistence() async throws {
        let signatureFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: signatureFixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: signatureFixture.now)
        let valid = try makeEnvelope(
            key: signatureFixture.key,
            now: signatureFixture.now,
            regions: [region]
        )
        var damaged = valid.signature
        damaged[damaged.startIndex] ^= 0x01
        let badSignature = try OfflineCoverageSignedEnvelope(
            keyID: valid.keyID,
            algorithm: valid.algorithm,
            payload: valid.payload,
            signature: damaged
        )
        await assertInstallError(.invalidSignature, envelope: badSignature, resolver: signatureFixture.resolver)

        let keyFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: keyFixture.root) }
        let unknownKey = try OfflineCoverageSignedEnvelope(
            keyID: "untrusted-key",
            algorithm: valid.algorithm,
            payload: valid.payload,
            signature: valid.signature
        )
        await assertInstallError(.untrustedSigningKey, envelope: unknownKey, resolver: keyFixture.resolver)

        let claimFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: claimFixture.root) }
        let wrongClaims = try makeEnvelope(
            key: claimFixture.key,
            now: claimFixture.now,
            issuer: "https://attacker.invalid",
            regions: [try makeRegion(id: "here:region:alpha", now: claimFixture.now)]
        )
        await assertInstallError(.signedClaimMismatch, envelope: wrongClaims, resolver: claimFixture.resolver)

        XCTAssertFalse(FileManager.default.fileExists(atPath: signatureFixture.manifestURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: keyFixture.manifestURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimFixture.manifestURL.path))
    }

    func testExpiredManifestAndExpiredSourceRightsFailClosed() async throws {
        let expiredManifestFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: expiredManifestFixture.root) }
        let now = expiredManifestFixture.now
        let expiredRegion = try makeRegion(
            id: "here:region:expired",
            now: now,
            validFrom: now.addingTimeInterval(-2_000),
            validUntil: now.addingTimeInterval(-700)
        )
        let expiredManifest = try makeEnvelope(
            key: expiredManifestFixture.key,
            now: now,
            issuedAt: now.addingTimeInterval(-1_000),
            validFrom: now.addingTimeInterval(-3_000),
            validUntil: now.addingTimeInterval(-600),
            sourceValidFrom: now.addingTimeInterval(-4_000),
            sourceValidUntil: now.addingTimeInterval(3_600),
            regions: [expiredRegion]
        )
        await assertInstallError(
            .expiredManifest,
            envelope: expiredManifest,
            resolver: expiredManifestFixture.resolver
        )

        let rightsFixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: rightsFixture.root) }
        let rightsRegion = try makeRegion(
            id: "here:region:rights-expired",
            now: now,
            validFrom: now.addingTimeInterval(-2_000),
            validUntil: now.addingTimeInterval(-700)
        )
        let expiredRights = try makeEnvelope(
            key: rightsFixture.key,
            now: now,
            validFrom: now.addingTimeInterval(-3_000),
            validUntil: now.addingTimeInterval(3_600),
            sourceValidFrom: now.addingTimeInterval(-4_000),
            sourceValidUntil: now.addingTimeInterval(-600),
            regions: [rightsRegion]
        )
        await assertInstallError(
            .sourceRightsExpired,
            envelope: expiredRights,
            resolver: rightsFixture.resolver
        )
    }

    func testRevokedRegionIsNeverReturnedAsCoverage() async throws {
        let fixture = try makeFixture(installedIDs: ["here:region:revoked"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let revoked = try makeRegion(
            id: "here:region:revoked",
            now: fixture.now,
            status: .revoked
        )
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [revoked])
        )

        do {
            _ = try await fixture.resolver.resolveInstalledCoverage(for: .point(try coordinate(5, 5)))
            XCTFail("Revoked coverage must fail closed.")
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(error, .revokedRegion(try OfflineMapRegionID("here:region:revoked")))
        }
    }

    func testInstalledCatalogMustExactlyMatchSignedCatalog() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )
        fixture.state.setInventory(
            try HEREInstalledRegionInventory(
                catalogVersion: HEREOfflineCatalogVersion("different-catalog"),
                usableRegionIDs: [try OfflineMapRegionID("here:region:alpha")],
                observedAt: fixture.now
            )
        )

        do {
            _ = try await fixture.resolver.resolveInstalledCoverage(for: .point(try coordinate(5, 5)))
            XCTFail("A catalog mismatch must not produce coverage evidence.")
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(
                error,
                .catalogMismatch(
                    expected: fixture.catalog,
                    actual: try HEREOfflineCatalogVersion("different-catalog")
                )
            )
        }
    }

    func testHoleAndDisconnectedMultipolygonRemainOutside() async throws {
        let fixture = try makeFixture(installedIDs: ["here:region:islands"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try OfflineCoveragePolygon(
            exterior: rectangle(minLatitude: 0, minLongitude: 0, maxLatitude: 10, maxLongitude: 10),
            holes: [rectangle(minLatitude: 4, minLongitude: 4, maxLatitude: 6, maxLongitude: 6)]
        )
        let second = try OfflineCoveragePolygon(
            exterior: rectangle(minLatitude: 20, minLongitude: 20, maxLatitude: 22, maxLongitude: 22)
        )
        let region = try makeRegion(
            id: "here:region:islands",
            now: fixture.now,
            boundary: OfflineCoverageMultiPolygon(polygons: [first, second])
        )
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )

        let hole = try await fixture.resolver.resolveInstalledCoverage(for: .point(try coordinate(5, 5)))
        XCTAssertEqual(hole.classification, .outside)
        let gap = try await fixture.resolver.resolveInstalledCoverage(for: .point(try coordinate(15, 15)))
        XCTAssertEqual(gap.classification, .outside)
        let secondIsland = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(21, 21))
        )
        XCTAssertNotNil(secondIsland.classification.evidence)

        let crossingHole = try OfflineCoverageRequestGeometry.routeCorridor(
            coordinates: [try coordinate(5, 3), try coordinate(5, 7)]
        )
        let corridor = try await fixture.resolver.resolveInstalledCoverage(for: crossingHole)
        XCTAssertEqual(corridor.classification, .outside)
    }

    func testDatelineCrossingBoundaryClassifiesBothSidesWithoutBoundingBoxGuess() async throws {
        let fixture = try makeFixture(installedIDs: ["here:region:dateline"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let datelineBoundary = try OfflineCoverageMultiPolygon(
            polygons: [
                OfflineCoveragePolygon(
                    exterior: try OfflineCoverageLinearRing(coordinates: [
                        coordinate(-10, 170), coordinate(-10, -170),
                        coordinate(10, -170), coordinate(10, 170),
                        coordinate(-10, 170)
                    ])
                )
            ]
        )
        let region = try makeRegion(
            id: "here:region:dateline",
            now: fixture.now,
            boundary: datelineBoundary
        )
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )

        let east = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(0, 179))
        )
        XCTAssertNotNil(east.classification.evidence)
        let west = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(0, -179))
        )
        XCTAssertNotNil(west.classification.evidence)
        let primeMeridian = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(0, 0))
        )
        XCTAssertEqual(primeMeridian.classification, .outside)
    }

    func testPartialRouteCorridorAndUncoveredCoordinateFailClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )
        let partlyOutside = try OfflineCoverageRequestGeometry.routeCorridor(
            coordinates: [try coordinate(5, 5), try coordinate(5, 12)]
        )
        let partialResult = try await fixture.resolver.resolveInstalledCoverage(for: partlyOutside)
        XCTAssertEqual(partialResult.classification, .outside)
        XCTAssertEqual(partialResult.coordinateClassifications.count, 2)
        XCTAssertNotNil(partialResult.coordinateClassifications[0].classification.evidence)
        XCTAssertEqual(partialResult.coordinateClassifications[1].classification, .outside)

        let oversizedCorridor = try OfflineCoverageRequestGeometry.routeCorridor(
            coordinates: [try coordinate(5, 2), try coordinate(5, 8)],
            halfWidthMeters: 600_000
        )
        let oversizedResult = try await fixture.resolver.resolveInstalledCoverage(for: oversizedCorridor)
        XCTAssertEqual(oversizedResult.classification, .outside)
    }

    func testSignedRegionMustAlsoBeInstalled() async throws {
        let fixture = try makeFixture(installedIDs: [])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )

        let resolution = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(5, 5))
        )
        XCTAssertEqual(resolution.classification, .outside)
        XCTAssertNil(resolution.classification.evidence)
    }

    func testOverlappingInstalledRegionsReturnDeterministicExactAttribution() async throws {
        let fixture = try makeFixture(installedIDs: ["here:region:zeta", "here:region:alpha"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let zeta = try makeRegion(id: "here:region:zeta", now: fixture.now)
        let alpha = try makeRegion(id: "here:region:alpha", now: fixture.now)
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [zeta, alpha])
        )

        let result = try await fixture.resolver.resolveInstalledCoverage(
            for: .gnssSample(try coordinate(5, 5))
        )
        XCTAssertEqual(
            result.classification.evidence?.regionIDs.map(\.rawValue),
            ["here:region:alpha", "here:region:zeta"]
        )
    }

    func testBoundaryWarningThresholdDistinguishesApproachingFromVerifiedInside() async throws {
        let fixture = try makeFixture(boundaryWarningMeters: 2_000)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )

        let near = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(5, 0.01))
        )
        guard case .approachingBoundary(let evidence, let distance) = near.classification else {
            XCTFail("A point within the configured warning distance must be approaching the boundary.")
            return
        }
        XCTAssertEqual(evidence.regionIDs.map(\.rawValue), ["here:region:alpha"])
        XCTAssertGreaterThan(distance, 900)
        XCTAssertLessThan(distance, 1_300)

        let interior = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(5, 5))
        )
        guard case .verifiedInside = interior.classification else {
            XCTFail("A point safely inside the region must remain verified inside.")
            return
        }
    }

    func testSearchAreaRequiresWholePolygonAndRejectsEnclosedHole() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let polygon = try OfflineCoveragePolygon(
            exterior: rectangle(minLatitude: 0, minLongitude: 0, maxLatitude: 10, maxLongitude: 10),
            holes: [rectangle(minLatitude: 4, minLongitude: 4, maxLatitude: 6, maxLongitude: 6)]
        )
        let region = try makeRegion(
            id: "here:region:alpha",
            now: fixture.now,
            boundary: OfflineCoverageMultiPolygon(polygons: [polygon])
        )
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )

        let safeArea = try OfflineCoverageRequestGeometry.searchArea(boundary: [
            coordinate(1, 1), coordinate(1, 2), coordinate(2, 2), coordinate(2, 1), coordinate(1, 1)
        ])
        let safeAreaResult = try await fixture.resolver.resolveInstalledCoverage(for: safeArea)
        XCTAssertNotNil(safeAreaResult.classification.evidence)

        let areaAroundHole = try OfflineCoverageRequestGeometry.searchArea(boundary: [
            coordinate(3, 3), coordinate(3, 7), coordinate(7, 7), coordinate(7, 3), coordinate(3, 3)
        ])
        let holeAreaResult = try await fixture.resolver.resolveInstalledCoverage(for: areaAroundHole)
        XCTAssertEqual(holeAreaResult.classification, .outside)
    }

    func testOlderAndConflictingSameSequenceManifestsAreRejected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        let sequenceTwo = try makeEnvelope(
            key: fixture.key,
            now: fixture.now,
            manifestID: "manifest-two",
            sequence: 2,
            regions: [region]
        )
        _ = try await fixture.resolver.installSignedManifest(sequenceTwo)

        let older = try makeEnvelope(
            key: fixture.key,
            now: fixture.now.addingTimeInterval(-60),
            manifestID: "manifest-one",
            sequence: 1,
            regions: [try makeRegion(id: "here:region:alpha", now: fixture.now.addingTimeInterval(-60))]
        )
        await assertInstallError(.replayRejected, envelope: older, resolver: fixture.resolver)

        let conflicting = try makeEnvelope(
            key: fixture.key,
            now: fixture.now,
            manifestID: "manifest-two-conflict",
            sequence: 2,
            regions: [region]
        )
        await assertInstallError(.replayRejected, envelope: conflicting, resolver: fixture.resolver)

        let idempotent = try await fixture.resolver.installSignedManifest(sequenceTwo)
        XCTAssertEqual(idempotent.payload.manifestID, "manifest-two")
    }

    func testWallClockRollbackCannotReviveAcceptedCoverage() async throws {
        let fixture = try makeFixture(allowedClockSkew: 5)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )
        fixture.state.setTime(fixture.now.addingTimeInterval(-600))

        do {
            _ = try await fixture.resolver.resolveInstalledCoverage(for: .point(try coordinate(5, 5)))
            XCTFail("A clock rollback behind accepted evidence must fail closed.")
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(error, .clockRollbackDetected)
        }
    }

    func testCorruptPersistenceNeverProducesCoverageEvidence() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        let envelope = try makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        _ = try await fixture.resolver.installSignedManifest(envelope)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.manifestURL.path))

        try Data("corrupt".utf8).write(to: fixture.manifestURL, options: .atomic)
        do {
            _ = try await fixture.resolver.resolveInstalledCoverage(for: .point(try coordinate(5, 5)))
            XCTFail("Corrupt persisted bytes must never produce installed coverage.")
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(error, .persistenceCorrupt)
        }
    }

    func testStaleNativeInventoryFailsClosed() async throws {
        let fixture = try makeFixture(maximumInventoryAge: 60)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )
        fixture.state.setInventory(
            try HEREInstalledRegionInventory(
                catalogVersion: fixture.catalog,
                usableRegionIDs: [try OfflineMapRegionID("here:region:alpha")],
                observedAt: fixture.now.addingTimeInterval(-1_000)
            )
        )

        do {
            _ = try await fixture.resolver.resolveInstalledCoverage(for: .point(try coordinate(5, 5)))
            XCTFail("Stale native inventory must fail closed.")
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(error, .inventoryTooOld)
        }
    }

    // MARK: - Fixtures

    private struct Fixture {
        let root: URL
        let manifestURL: URL
        let now: Date
        let catalog: HEREOfflineCatalogVersion
        let key: Curve25519.Signing.PrivateKey
        let state: LockedCoverageTestState
        let resolver: SignedInstalledCoverageResolver
    }

    private func makeFixture(
        installedIDs: [String] = ["here:region:alpha"],
        boundaryWarningMeters: Double = 1_000,
        maximumInventoryAge: TimeInterval = 900,
        allowedClockSkew: TimeInterval = 300
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("signed-coverage-tests-\(UUID().uuidString)", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let catalog = try HEREOfflineCatalogVersion("here-catalog-2026-08")
        let key = Curve25519.Signing.PrivateKey()
        let verificationKey = try OfflineCoverageVerificationKey(
            keyID: keyID,
            ed25519RawRepresentation: key.publicKey.rawRepresentation
        )
        let verifier = try HEREOfflineCoverageManifestVerifier(
            expectedIssuer: issuer,
            expectedAudience: audience,
            expectedSDKVersion: sdkVersion,
            expectedRightsHolder: rightsHolder,
            keys: [verificationKey]
        )
        let inventory = try HEREInstalledRegionInventory(
            catalogVersion: catalog,
            usableRegionIDs: Set(try installedIDs.map(OfflineMapRegionID.init)),
            observedAt: now
        )
        let state = LockedCoverageTestState(time: now, inventory: inventory)
        let provider = AnyHEREInstalledRegionInventoryProvider { state.inventory() }
        let resolver = try SignedInstalledCoverageResolver(
            rootDirectory: root,
            verifier: verifier,
            inventoryProvider: provider,
            boundaryWarningMeters: boundaryWarningMeters,
            maximumInventoryAge: maximumInventoryAge,
            allowedClockSkew: allowedClockSkew,
            currentTime: { state.time() }
        )
        return Fixture(
            root: root,
            manifestURL: root
                .appendingPathComponent("here-installed-coverage", isDirectory: true)
                .appendingPathComponent("v1-signed-manifest.json"),
            now: now,
            catalog: catalog,
            key: key,
            state: state,
            resolver: resolver
        )
    }

    private func makeEnvelope(
        key: Curve25519.Signing.PrivateKey,
        now: Date,
        issuedAt: Date? = nil,
        issuer: String? = nil,
        manifestID: String = "manifest-1",
        sequence: UInt64 = 1,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        sourceValidFrom: Date? = nil,
        sourceValidUntil: Date? = nil,
        regions: [HEREOfflineSignedRegion]
    ) throws -> OfflineCoverageSignedEnvelope {
        let manifestValidFrom = validFrom ?? now.addingTimeInterval(-3_600)
        let manifestValidUntil = validUntil ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        let source = try HEREOfflineCoverageSource(
            sdkVersion: sdkVersion,
            rightsID: "here-rights-test",
            rightsHolder: rightsHolder,
            rightsValidFrom: sourceValidFrom ?? now.addingTimeInterval(-7_200),
            rightsValidUntil: sourceValidUntil ?? now.addingTimeInterval(30 * 24 * 60 * 60)
        )
        let payload = try HEREOfflineSignedCoverageManifest(
            issuer: issuer ?? self.issuer,
            audience: audience,
            manifestID: manifestID,
            sequence: sequence,
            issuedAt: issuedAt ?? now,
            validFrom: manifestValidFrom,
            validUntil: manifestValidUntil,
            catalogVersion: HEREOfflineCatalogVersion("here-catalog-2026-08"),
            source: source,
            regions: regions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(payload)
        return try OfflineCoverageSignedEnvelope(
            keyID: keyID,
            algorithm: .ed25519,
            payload: bytes,
            signature: try key.signature(for: bytes)
        )
    }

    private func makeRegion(
        id: String,
        now: Date,
        status: OfflineCoverageRegionStatus = .active,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        boundary: OfflineCoverageMultiPolygon? = nil
    ) throws -> HEREOfflineSignedRegion {
        try HEREOfflineSignedRegion(
            regionID: OfflineMapRegionID(id),
            catalogVersion: HEREOfflineCatalogVersion("here-catalog-2026-08"),
            status: status,
            validFrom: validFrom ?? now.addingTimeInterval(-1_800),
            validUntil: validUntil ?? now.addingTimeInterval(24 * 60 * 60),
            rightsID: "here-rights-test",
            boundary: boundary ?? OfflineCoverageMultiPolygon(
                polygons: [
                    OfflineCoveragePolygon(
                        exterior: rectangle(
                            minLatitude: 0,
                            minLongitude: 0,
                            maxLatitude: 10,
                            maxLongitude: 10
                        )
                    )
                ]
            )
        )
    }

    private func rectangle(
        minLatitude: Double,
        minLongitude: Double,
        maxLatitude: Double,
        maxLongitude: Double
    ) throws -> OfflineCoverageLinearRing {
        try OfflineCoverageLinearRing(coordinates: [
            coordinate(minLatitude, minLongitude),
            coordinate(minLatitude, maxLongitude),
            coordinate(maxLatitude, maxLongitude),
            coordinate(maxLatitude, minLongitude),
            coordinate(minLatitude, minLongitude)
        ])
    }

    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> OfflineGeoCoordinate {
        try OfflineGeoCoordinate(latitude: latitude, longitude: longitude)
    }

    private func assertInstallError(
        _ expected: SignedInstalledCoverageError,
        envelope: OfflineCoverageSignedEnvelope,
        resolver: SignedInstalledCoverageResolver,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await resolver.installSignedManifest(envelope)
            XCTFail("Expected signed coverage installation to fail.", file: file, line: line)
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
