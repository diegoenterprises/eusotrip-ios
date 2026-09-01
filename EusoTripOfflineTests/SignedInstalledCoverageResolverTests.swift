import CryptoKit
import Foundation

#if !SIGNED_COVERAGE_SOURCE_VERIFICATION
import XCTest
@testable import EusoTrip
#endif

private final class LockedCoverageTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var timeValue: Date
    private var uptimeValue: TimeInterval
    private var bootSessionValue: String?
    private var inventoryValue: HEREInstalledRegionInventory

    init(
        time: Date,
        uptime: TimeInterval = 100,
        bootSession: String? = "boot-a",
        inventory: HEREInstalledRegionInventory
    ) {
        timeValue = time
        uptimeValue = uptime
        bootSessionValue = bootSession
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

    func uptime() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return uptimeValue
    }

    func setUptime(_ value: TimeInterval) {
        lock.lock()
        uptimeValue = value
        lock.unlock()
    }

    func bootSession() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return bootSessionValue
    }

    func setBootSession(_ value: String?) {
        lock.lock()
        bootSessionValue = value
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

private final class LockedCoverageAnchorPersistence:
    SignedCoverageTrustedAnchorPersistence,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var value: Data?

    func load() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func save(_ data: Data) throws {
        lock.lock()
        value = data
        lock.unlock()
    }

    func remove() throws {
        lock.lock()
        value = nil
        lock.unlock()
    }

    func replace(_ data: Data?) {
        lock.lock()
        value = data
        lock.unlock()
    }
}

#if !SIGNED_COVERAGE_SOURCE_VERIFICATION
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

    func testWallClockRollbackAfterAcceptanceDoesNotChangeTrustedCoverageTime() async throws {
        let fixture = try makeFixture(allowedClockSkew: 5)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        fixture.state.setTime(fixture.now.addingTimeInterval(600))
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )
        fixture.state.setTime(fixture.now.addingTimeInterval(-600))

        let resolution = try await fixture.resolver.resolveInstalledCoverage(
            for: .point(try coordinate(5, 5))
        )
        XCTAssertEqual(resolution.evaluatedAt, fixture.now)
        XCTAssertNotNil(resolution.classification.evidence)
    }

    func testSameBootProcessRelaunchResumesCoverageFromMonotonicAnchor() async throws {
        let fixture = try makeFixture(allowedClockSkew: 5)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let region = try makeRegion(id: "here:region:alpha", now: fixture.now)
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(key: fixture.key, now: fixture.now, regions: [region])
        )

        fixture.resolverStorage.value = nil
        fixture.state.setUptime(160)
        fixture.state.setTime(fixture.now.addingTimeInterval(-86_400))
        fixture.state.setInventory(
            try HEREInstalledRegionInventory(
                catalogVersion: fixture.catalog,
                usableRegionIDs: [try OfflineMapRegionID("here:region:alpha")],
                observedAt: fixture.now.addingTimeInterval(60)
            )
        )
        let relaunched = try makeResolver(for: fixture)
        fixture.resolverStorage.value = relaunched

        let resolution = try await relaunched.resolveInstalledCoverage(
            for: .point(try coordinate(5, 5))
        )
        XCTAssertEqual(
            resolution.evaluatedAt,
            fixture.now.addingTimeInterval(60)
        )
        XCTAssertNotNil(resolution.classification.evidence)
    }

    func testRebootCannotReuseOrReinstallTheSameSignedCoverageManifest() async throws {
        let fixture = try makeFixture(allowedClockSkew: 5)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let envelope = try makeEnvelope(
            key: fixture.key,
            now: fixture.now,
            regions: [try makeRegion(id: "here:region:alpha", now: fixture.now)]
        )
        _ = try await fixture.resolver.installSignedManifest(envelope)

        fixture.resolverStorage.value = nil
        fixture.state.setBootSession("boot-b")
        fixture.state.setUptime(20)
        let rebooted = try makeResolver(for: fixture)
        fixture.resolverStorage.value = rebooted

        await assertInstallError(
            .bootSessionChanged,
            envelope: envelope,
            resolver: rebooted
        )
        do {
            _ = try await rebooted.resolveInstalledCoverage(
                for: .point(try coordinate(5, 5))
            )
            XCTFail("A new boot must not reuse persisted installed-coverage time.")
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(error, .bootSessionChanged)
        }
    }

    func testSameBootRelaunchWithUptimeBehindAnchorInvalidatesCoverage() async throws {
        let fixture = try makeFixture(allowedClockSkew: 5)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(
                key: fixture.key,
                now: fixture.now,
                regions: [try makeRegion(id: "here:region:alpha", now: fixture.now)]
            )
        )
        fixture.resolverStorage.value = nil
        fixture.state.setUptime(99)
        let relaunched = try makeResolver(for: fixture)
        fixture.resolverStorage.value = relaunched

        do {
            _ = try await relaunched.resolveInstalledCoverage(
                for: .point(try coordinate(5, 5))
            )
            XCTFail("A monotonic uptime rollback must invalidate installed coverage.")
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(error, .monotonicUptimeRegressed)
        }
    }

    func testTrustedAnchorTamperNeverProducesCoverage() async throws {
        let fixture = try makeFixture(allowedClockSkew: 5)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(
                key: fixture.key,
                now: fixture.now,
                regions: [try makeRegion(id: "here:region:alpha", now: fixture.now)]
            )
        )
        let anchorData = try XCTUnwrap(fixture.persistence.load())
        var anchor = try XCTUnwrap(
            JSONSerialization.jsonObject(with: anchorData) as? [String: Any]
        )
        anchor["envelopeSHA256"] = String(repeating: "0", count: 64)
        fixture.persistence.replace(
            try JSONSerialization.data(withJSONObject: anchor, options: [.sortedKeys])
        )

        do {
            _ = try await fixture.resolver.resolveInstalledCoverage(
                for: .point(try coordinate(5, 5))
            )
            XCTFail("A changed trusted-time anchor must never produce coverage.")
        } catch let error as SignedInstalledCoverageError {
            XCTAssertEqual(error, .persistenceCorrupt)
        }
    }

    func testExpiredCoverageCannotBeRevivedByWallClockRollback() async throws {
        let fixture = try makeFixture(allowedClockSkew: 5)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let validUntil = fixture.now.addingTimeInterval(30)
        let region = try makeRegion(
            id: "here:region:alpha",
            now: fixture.now,
            validUntil: validUntil
        )
        _ = try await fixture.resolver.installSignedManifest(
            makeEnvelope(
                key: fixture.key,
                now: fixture.now,
                validUntil: validUntil,
                regions: [region]
            )
        )
        fixture.state.setUptime(500)

        for wallTime in [
            fixture.now.addingTimeInterval(60),
            fixture.now.addingTimeInterval(-86_400),
        ] {
            fixture.state.setTime(wallTime)
            do {
                _ = try await fixture.resolver.resolveInstalledCoverage(
                    for: .point(try coordinate(5, 5))
                )
                XCTFail("Expired coverage must remain expired after wall-clock rollback.")
            } catch let error as SignedInstalledCoverageError {
                XCTAssertEqual(error, .expiredManifest)
            }
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

    private final class ResolverStorage {
        var value: SignedInstalledCoverageResolver?

        init(_ value: SignedInstalledCoverageResolver) {
            self.value = value
        }
    }

    private struct Fixture {
        let root: URL
        let manifestURL: URL
        let now: Date
        let catalog: HEREOfflineCatalogVersion
        let key: Curve25519.Signing.PrivateKey
        let state: LockedCoverageTestState
        let verifier: HEREOfflineCoverageManifestVerifier
        let provider: AnyHEREInstalledRegionInventoryProvider
        let persistence: LockedCoverageAnchorPersistence
        let boundaryWarningMeters: Double
        let maximumInventoryAge: TimeInterval
        let allowedClockSkew: TimeInterval
        let resolverStorage: ResolverStorage

        var resolver: SignedInstalledCoverageResolver {
            guard let value = resolverStorage.value else {
                preconditionFailure("The focused coverage test released its resolver too early.")
            }
            return value
        }
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
        let persistence = LockedCoverageAnchorPersistence()
        let resolver = try SignedInstalledCoverageResolver(
            rootDirectory: root,
            verifier: verifier,
            inventoryProvider: provider,
            boundaryWarningMeters: boundaryWarningMeters,
            maximumInventoryAge: maximumInventoryAge,
            allowedClockSkew: allowedClockSkew,
            currentTime: { state.time() },
            monotonicUptime: { state.uptime() },
            bootSessionIdentifier: { state.bootSession() },
            trustedAnchorPersistence: persistence
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
            verifier: verifier,
            provider: provider,
            persistence: persistence,
            boundaryWarningMeters: boundaryWarningMeters,
            maximumInventoryAge: maximumInventoryAge,
            allowedClockSkew: allowedClockSkew,
            resolverStorage: ResolverStorage(resolver)
        )
    }

    private func makeResolver(for fixture: Fixture) throws -> SignedInstalledCoverageResolver {
        let state = fixture.state
        try SignedInstalledCoverageResolver(
            rootDirectory: fixture.root,
            verifier: fixture.verifier,
            inventoryProvider: fixture.provider,
            boundaryWarningMeters: fixture.boundaryWarningMeters,
            maximumInventoryAge: fixture.maximumInventoryAge,
            allowedClockSkew: fixture.allowedClockSkew,
            currentTime: { state.time() },
            monotonicUptime: { state.uptime() },
            bootSessionIdentifier: { state.bootSession() },
            trustedAnchorPersistence: fixture.persistence
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
#else
private enum SignedCoverageSourceVerificationError: Error {
    case failed(String)
}

@main
private struct SignedCoverageSourceVerification {
    private static let issuer = "https://coverage.eusotrip.test"
    private static let audience = "com.app.eusotrip"
    private static let sdkVersion = "4.27.2.0"
    private static let rightsHolder = "HERE Global B.V."
    private static let keyID = "here-coverage-source-test-key"

    static func main() async throws {
        try await verifySameBootRelaunch()
        try await verifyRebootFailsClosed()
        try await verifyUptimeRollbackFailsClosed()
        try await verifyAnchorTamperFailsClosed()
        try await verifyExpiryCannotBeRevivedByWallClockRollback()
        print("Signed installed-coverage trusted-time verification passed: 5 cases")
    }

    private static func verifySameBootRelaunch() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var first: SignedInstalledCoverageResolver? = try fixture.makeResolver()
        fixture.state.setTime(fixture.now.addingTimeInterval(600))
        _ = try await first?.installSignedManifest(fixture.envelope)
        first = nil

        fixture.state.setUptime(160)
        fixture.state.setTime(fixture.now.addingTimeInterval(-86_400))
        fixture.state.setInventory(
            try HEREInstalledRegionInventory(
                catalogVersion: fixture.catalog,
                usableRegionIDs: [try OfflineMapRegionID("here:region:alpha")],
                observedAt: fixture.now.addingTimeInterval(60)
            )
        )
        let relaunched = try fixture.makeResolver()
        let resolution = try await relaunched.resolveInstalledCoverage(
            for: .point(try coordinate(5, 5))
        )
        try require(
            resolution.evaluatedAt == fixture.now.addingTimeInterval(60),
            "same-boot relaunch did not resume monotonic coverage time"
        )
    }

    private static func verifyRebootFailsClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var first: SignedInstalledCoverageResolver? = try fixture.makeResolver()
        _ = try await first?.installSignedManifest(fixture.envelope)
        first = nil

        fixture.state.setBootSession("boot-b")
        fixture.state.setUptime(20)
        let rebooted = try fixture.makeResolver()
        try await requireError(.bootSessionChanged) {
            _ = try await rebooted.resolveInstalledCoverage(
                for: .point(try coordinate(5, 5))
            )
        }
    }

    private static func verifyUptimeRollbackFailsClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var first: SignedInstalledCoverageResolver? = try fixture.makeResolver()
        _ = try await first?.installSignedManifest(fixture.envelope)
        first = nil
        fixture.state.setUptime(99)
        let relaunched = try fixture.makeResolver()
        try await requireError(.monotonicUptimeRegressed) {
            _ = try await relaunched.resolveInstalledCoverage(
                for: .point(try coordinate(5, 5))
            )
        }
    }

    private static func verifyAnchorTamperFailsClosed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let resolver = try fixture.makeResolver()
        _ = try await resolver.installSignedManifest(fixture.envelope)
        let data = try requireValue(fixture.persistence.load(), "trusted anchor was not persisted")
        var object = try requireValue(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            "trusted anchor was not JSON"
        )
        object["envelopeSHA256"] = String(repeating: "0", count: 64)
        fixture.persistence.replace(
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
        try await requireError(.persistenceCorrupt) {
            _ = try await resolver.resolveInstalledCoverage(
                for: .point(try coordinate(5, 5))
            )
        }
    }

    private static func verifyExpiryCannotBeRevivedByWallClockRollback() async throws {
        let fixture = try makeFixture(validity: 30)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let resolver = try fixture.makeResolver()
        _ = try await resolver.installSignedManifest(fixture.envelope)
        fixture.state.setUptime(500)

        for wallTime in [
            fixture.now.addingTimeInterval(60),
            fixture.now.addingTimeInterval(-86_400),
        ] {
            fixture.state.setTime(wallTime)
            try await requireError(.expiredManifest) {
                _ = try await resolver.resolveInstalledCoverage(
                    for: .point(try coordinate(5, 5))
                )
            }
        }
    }

    private final class Fixture {
        let root: URL
        let now: Date
        let catalog: HEREOfflineCatalogVersion
        let state: LockedCoverageTestState
        let persistence: LockedCoverageAnchorPersistence
        let verifier: HEREOfflineCoverageManifestVerifier
        let provider: AnyHEREInstalledRegionInventoryProvider
        let envelope: OfflineCoverageSignedEnvelope

        init(
            root: URL,
            now: Date,
            catalog: HEREOfflineCatalogVersion,
            state: LockedCoverageTestState,
            persistence: LockedCoverageAnchorPersistence,
            verifier: HEREOfflineCoverageManifestVerifier,
            provider: AnyHEREInstalledRegionInventoryProvider,
            envelope: OfflineCoverageSignedEnvelope
        ) {
            self.root = root
            self.now = now
            self.catalog = catalog
            self.state = state
            self.persistence = persistence
            self.verifier = verifier
            self.provider = provider
            self.envelope = envelope
        }

        func makeResolver() throws -> SignedInstalledCoverageResolver {
            try SignedInstalledCoverageResolver(
                rootDirectory: root,
                verifier: verifier,
                inventoryProvider: provider,
                boundaryWarningMeters: 1_000,
                maximumInventoryAge: 900,
                allowedClockSkew: 5,
                currentTime: { [state] in state.time() },
                monotonicUptime: { [state] in state.uptime() },
                bootSessionIdentifier: { [state] in state.bootSession() },
                trustedAnchorPersistence: persistence
            )
        }
    }

    private static func makeFixture(validity: TimeInterval = 24 * 60 * 60) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("signed-coverage-source-tests-\(UUID().uuidString)", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let catalog = try HEREOfflineCatalogVersion("here-catalog-2026-08")
        let key = Curve25519.Signing.PrivateKey()
        let verifier = try HEREOfflineCoverageManifestVerifier(
            expectedIssuer: issuer,
            expectedAudience: audience,
            expectedSDKVersion: sdkVersion,
            expectedRightsHolder: rightsHolder,
            keys: [
                try OfflineCoverageVerificationKey(
                    keyID: keyID,
                    ed25519RawRepresentation: key.publicKey.rawRepresentation
                ),
            ]
        )
        let region = try HEREOfflineSignedRegion(
            regionID: OfflineMapRegionID("here:region:alpha"),
            catalogVersion: catalog,
            status: .active,
            validFrom: now.addingTimeInterval(-1_800),
            validUntil: now.addingTimeInterval(validity),
            rightsID: "here-rights-source-test",
            boundary: try rectangle()
        )
        let source = try HEREOfflineCoverageSource(
            sdkVersion: sdkVersion,
            rightsID: "here-rights-source-test",
            rightsHolder: rightsHolder,
            rightsValidFrom: now.addingTimeInterval(-7_200),
            rightsValidUntil: now.addingTimeInterval(30 * 24 * 60 * 60)
        )
        let payload = try HEREOfflineSignedCoverageManifest(
            issuer: issuer,
            audience: audience,
            manifestID: "manifest-source-test",
            sequence: 1,
            issuedAt: now,
            validFrom: now.addingTimeInterval(-3_600),
            validUntil: now.addingTimeInterval(validity),
            catalogVersion: catalog,
            source: source,
            regions: [region]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(payload)
        let envelope = try OfflineCoverageSignedEnvelope(
            keyID: keyID,
            algorithm: .ed25519,
            payload: payloadData,
            signature: try key.signature(for: payloadData)
        )
        let inventory = try HEREInstalledRegionInventory(
            catalogVersion: catalog,
            usableRegionIDs: [try OfflineMapRegionID("here:region:alpha")],
            observedAt: now
        )
        let state = LockedCoverageTestState(time: now, inventory: inventory)
        let provider = AnyHEREInstalledRegionInventoryProvider { state.inventory() }
        return Fixture(
            root: root,
            now: now,
            catalog: catalog,
            state: state,
            persistence: LockedCoverageAnchorPersistence(),
            verifier: verifier,
            provider: provider,
            envelope: envelope
        )
    }

    private static func rectangle() throws -> OfflineCoverageMultiPolygon {
        try OfflineCoverageMultiPolygon(
            polygons: [
                OfflineCoveragePolygon(
                    exterior: OfflineCoverageLinearRing(
                        coordinates: [
                            coordinate(0, 0),
                            coordinate(0, 10),
                            coordinate(10, 10),
                            coordinate(10, 0),
                            coordinate(0, 0),
                        ]
                    )
                ),
            ]
        )
    }

    private static func coordinate(
        _ latitude: Double,
        _ longitude: Double
    ) throws -> OfflineGeoCoordinate {
        try OfflineGeoCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func requireError(
        _ expected: SignedInstalledCoverageError,
        operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
            throw SignedCoverageSourceVerificationError.failed(
                "expected \(expected), but the operation succeeded"
            )
        } catch let error as SignedInstalledCoverageError {
            try require(error == expected, "expected \(expected), received \(error)")
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw SignedCoverageSourceVerificationError.failed(message)
        }
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw SignedCoverageSourceVerificationError.failed(message)
        }
        return value
    }
}
#endif
