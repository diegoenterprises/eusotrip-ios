import Foundation

private enum TrustedClockVerificationError: Error {
    case failed(String)
}

private final class VerificationAnchorPersistence:
    CanonicalRouteTrustedAnchorPersistence,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [CanonicalRoutePrincipal: Data] = [:]

    func load(for principal: CanonicalRoutePrincipal) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[principal]
    }

    func save(_ data: Data, for principal: CanonicalRoutePrincipal) throws {
        lock.lock()
        values[principal] = data
        lock.unlock()
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

@main
private struct CanonicalRouteTrustedClockVerification {
    static func main() throws {
        try verifySameBootRelaunch()
        try verifyRebootFailsClosed()
        try verifyUptimeRollbackFailsClosed()
        try verifyMalformedPersistenceFailsClosed()
        try verifyInvalidationPreventsReuse()
        print("Canonical route trusted-clock verification passed: 5 cases")
    }

    private static func verifySameBootRelaunch() throws {
        let persistence = VerificationAnchorPersistence()
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
        try require(
            relaunched.reading(for: principal) ==
                .trusted(signedTime.addingTimeInterval(60)),
            "same-boot relaunch did not resume the monotonic anchor"
        )
    }

    private static func verifyRebootFailsClosed() throws {
        let persistence = VerificationAnchorPersistence()
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
        try require(
            rebooted.reading(for: principal) == .unavailable(.bootSessionChanged),
            "a new boot reused an old trusted-time anchor"
        )
    }

    private static func verifyUptimeRollbackFailsClosed() throws {
        let persistence = VerificationAnchorPersistence()
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
        try require(
            rolledBack.reading(for: principal) == .unavailable(
                .monotonicUptimeRegressed(
                    previousUptime: 500,
                    observedUptime: 499
                )
            ),
            "a same-boot uptime rollback was accepted"
        )
    }

    private static func verifyMalformedPersistenceFailsClosed() throws {
        let persistence = VerificationAnchorPersistence()
        let principal = try makePrincipal("malformed")
        persistence.replace(Data("not-json".utf8), for: principal)
        let clock = CanonicalRouteTrustedClock(
            monotonicUptime: { 100 },
            bootSessionIdentifier: { "boot-a" },
            persistence: persistence
        )
        try require(
            clock.reading(for: principal) == .unavailable(.persistedAnchorInvalid),
            "malformed persisted anchor was accepted"
        )
    }

    private static func verifyInvalidationPreventsReuse() throws {
        let persistence = VerificationAnchorPersistence()
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
        try require(
            relaunched.reading(for: principal) ==
                .unavailable(.authenticatedAnchorUnavailable),
            "invalidated anchor remained reusable"
        )
    }

    private static func makePrincipal(_ suffix: String) throws -> CanonicalRoutePrincipal {
        CanonicalRoutePrincipal(
            scope: try CanonicalRouteScope(
                tenantID: "tenant-\(suffix)",
                userID: "user-\(suffix)",
                loadID: "rail_shipment:42"
            )
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw TrustedClockVerificationError.failed(message)
        }
    }
}
