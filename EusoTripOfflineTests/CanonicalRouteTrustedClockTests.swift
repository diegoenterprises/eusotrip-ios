import Foundation
import XCTest
@testable import EusoTrip

private enum TrustedClockPersistenceFixtureError: Error {
    case refused
}

private final class InMemoryTrustedAnchorPersistence:
    CanonicalRouteTrustedAnchorPersistence,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [CanonicalRoutePrincipal: Data] = [:]
    var refusesWrites = false

    func load(for principal: CanonicalRoutePrincipal) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[principal]
    }

    func save(_ data: Data, for principal: CanonicalRoutePrincipal) throws {
        lock.lock()
        defer { lock.unlock() }
        if refusesWrites { throw TrustedClockPersistenceFixtureError.refused }
        values[principal] = data
    }

    func remove(for principal: CanonicalRoutePrincipal) throws {
        lock.lock()
        values.removeValue(forKey: principal)
        lock.unlock()
    }

    func removeAll() throws {
        lock.lock()
        values.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    func replace(_ data: Data, for principal: CanonicalRoutePrincipal) {
        lock.lock()
        values[principal] = data
        lock.unlock()
    }
}

final class CanonicalRouteTrustedClockTests: XCTestCase {
    func testSameBootProcessRelaunchResumesFromPersistedMonotonicAnchor() throws {
        let persistence = InMemoryTrustedAnchorPersistence()
        let principal = try makePrincipal("same-boot")
        let signedTime = Date(timeIntervalSince1970: 1_800_000_000)

        let first = CanonicalRouteTrustedClock(
            monotonicUptime: { 100 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        _ = try first.establishAuthenticatedAnchor(
            for: principal,
            signedServerTime: signedTime
        )

        let relaunched = CanonicalRouteTrustedClock(
            monotonicUptime: { 160 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        XCTAssertEqual(
            relaunched.reading(for: principal),
            .trusted(signedTime.addingTimeInterval(60))
        )
    }

    func testRebootCannotReusePersistedAnchor() throws {
        let persistence = InMemoryTrustedAnchorPersistence()
        let principal = try makePrincipal("reboot")
        let first = CanonicalRouteTrustedClock(
            monotonicUptime: { 900 },
            bootSessionIdentifier: { "boot-before" },
            persistence: persistence
        )
        _ = try first.establishAuthenticatedAnchor(
            for: principal,
            signedServerTime: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let rebooted = CanonicalRouteTrustedClock(
            monotonicUptime: { 20 },
            bootSessionIdentifier: { "boot-after" },
            persistence: persistence
        )
        XCTAssertEqual(
            rebooted.reading(for: principal),
            .unavailable(.bootSessionChanged)
        )
    }

    func testPersistedAnchorCannotCrossPrincipalScope() throws {
        let persistence = InMemoryTrustedAnchorPersistence()
        let firstPrincipal = try makePrincipal("principal-a")
        let otherPrincipal = try makePrincipal("principal-b")
        let first = CanonicalRouteTrustedClock(
            monotonicUptime: { 100 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        _ = try first.establishAuthenticatedAnchor(
            for: firstPrincipal,
            signedServerTime: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let relaunched = CanonicalRouteTrustedClock(
            monotonicUptime: { 200 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        XCTAssertEqual(
            relaunched.reading(for: otherPrincipal),
            .unavailable(.authenticatedAnchorUnavailable)
        )
    }

    func testMalformedPersistedAnchorFailsClosedAndIsRemoved() throws {
        let persistence = InMemoryTrustedAnchorPersistence()
        let principal = try makePrincipal("malformed")
        persistence.replace(Data("not-json".utf8), for: principal)
        let clock = CanonicalRouteTrustedClock(
            monotonicUptime: { 200 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )

        XCTAssertEqual(
            clock.reading(for: principal),
            .unavailable(.persistedAnchorInvalid)
        )
        let laterProcess = CanonicalRouteTrustedClock(
            monotonicUptime: { 201 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        XCTAssertEqual(
            laterProcess.reading(for: principal),
            .unavailable(.authenticatedAnchorUnavailable)
        )
    }

    func testSameBootUptimeRollbackInvalidatesPersistedAnchor() throws {
        let persistence = InMemoryTrustedAnchorPersistence()
        let principal = try makePrincipal("rollback")
        let first = CanonicalRouteTrustedClock(
            monotonicUptime: { 500 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        _ = try first.establishAuthenticatedAnchor(
            for: principal,
            signedServerTime: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let rolledBack = CanonicalRouteTrustedClock(
            monotonicUptime: { 499 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        XCTAssertEqual(
            rolledBack.reading(for: principal),
            .unavailable(
                .monotonicUptimeRegressed(
                    previousUptime: 500,
                    observedUptime: 499
                )
            )
        )
    }

    func testInvalidateAllPreventsLaterProcessReuse() throws {
        let persistence = InMemoryTrustedAnchorPersistence()
        let principal = try makePrincipal("purged")
        let first = CanonicalRouteTrustedClock(
            monotonicUptime: { 100 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        _ = try first.establishAuthenticatedAnchor(
            for: principal,
            signedServerTime: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try first.invalidateAll()

        let relaunched = CanonicalRouteTrustedClock(
            monotonicUptime: { 200 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        XCTAssertEqual(
            relaunched.reading(for: principal),
            .unavailable(.authenticatedAnchorUnavailable)
        )
    }

    func testPersistenceFailureRejectsNewAnchor() throws {
        let persistence = InMemoryTrustedAnchorPersistence()
        persistence.refusesWrites = true
        let clock = CanonicalRouteTrustedClock(
            monotonicUptime: { 100 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        XCTAssertThrowsError(
            try clock.establishAuthenticatedAnchor(
                for: makePrincipal("write-failure"),
                signedServerTime: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalRouteTrustedClockError,
                .anchorPersistenceUnavailable
            )
        }
    }

    private func makePrincipal(_ suffix: String) throws -> CanonicalRoutePrincipal {
        CanonicalRoutePrincipal(
            scope: try CanonicalRouteScope(
                tenantID: "tenant-\(suffix)",
                userID: "user-\(suffix)",
                loadID: "rail_shipment:42"
            )
        )
    }
}
