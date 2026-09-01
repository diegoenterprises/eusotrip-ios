import CryptoKit
import Foundation
import XCTest
@testable import EusoTrip

private final class LockedCanonicalRouteTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    private var uptimeValue: TimeInterval

    init(_ value: Date, uptime: TimeInterval = 10_000) {
        self.value = value
        uptimeValue = uptime
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ value: Date) {
        lock.lock()
        self.value = value
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

    func advanceUptime(by interval: TimeInterval) {
        lock.lock()
        uptimeValue += interval
        lock.unlock()
    }
}

final class CanonicalRoutePackageStoreTests: XCTestCase {
    private let issuer = "https://api.eusotrip.test"
    private let audience = "com.app.eusotrip"
    private let keyID = "offline-route-test-key"

    func testTenantUserAndLoadScopesRemainIsolated() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let clock = LockedCanonicalRouteTestClock(currentWholeSecond(), uptime: 100)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scopes = [
            try CanonicalRouteScope(tenantID: "tenant-a", userID: "user-a", loadID: "load-a"),
            try CanonicalRouteScope(tenantID: "tenant-b", userID: "user-a", loadID: "load-a"),
            try CanonicalRouteScope(tenantID: "tenant-a", userID: "user-b", loadID: "load-a"),
            try CanonicalRouteScope(tenantID: "tenant-a", userID: "user-a", loadID: "load-b")
        ]
        let observedAt = currentWholeSecond()
        for (index, scope) in scopes.enumerated() {
            let envelope = try makeSignedEnvelope(
                signingKey: signing.privateKey,
                scope: scope,
                routeID: "route-\(index)",
                generatedAt: observedAt.addingTimeInterval(-60),
                validUntil: observedAt.addingTimeInterval(3_600)
            )
            _ = try await store.store(
                signedEnvelope: envelope,
                expectedScope: scope,
                receivedAt: observedAt.addingTimeInterval(-30),
                storedAt: observedAt.addingTimeInterval(-20)
            )
        }
        let policy = try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)

        for (index, scope) in scopes.enumerated() {
            let observation = try await store.observe(scope: scope, policy: policy)
            XCTAssertEqual(observation.package?.routeID, "route-\(index)")
            XCTAssertEqual(observation.package?.scope, scope)
            XCTAssertEqual(observation.package?.provenance, .serverCanonical)
            XCTAssertEqual(observation.status, .fresh)
        }

        let missingScope = try CanonicalRouteScope(
            tenantID: "tenant-a",
            userID: "user-a",
            loadID: "load-never-stored"
        )
        let missing = try await store.observe(scope: missingScope, policy: policy)
        XCTAssertEqual(missing.status, .missing)
        XCTAssertNil(missing.package)
    }

    func testStaleServerObservationAndExpiredValidityRemainExplicit() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let now = currentWholeSecond()
        let clock = LockedCanonicalRouteTestClock(now)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-stale",
            userID: "user-stale",
            loadID: "load-stale"
        )
        let observedAt = currentWholeSecond()
        clock.set(observedAt)
        let validUntil = observedAt.addingTimeInterval(-30)
        let envelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "stale-rail-route",
            generatedAt: observedAt.addingTimeInterval(-300),
            issuedAt: observedAt.addingTimeInterval(-120),
            validUntil: validUntil
        )
        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: observedAt.addingTimeInterval(-120),
            storedAt: observedAt.addingTimeInterval(-100)
        )
        clock.advanceUptime(by: 120)
        let policy = try CanonicalRouteFreshnessPolicy(
            maximumServerObservationAge: 60,
            allowedClockSkew: 5
        )

        let observation = try await store.observe(scope: scope, policy: policy)

        guard case .stale(let reasons) = observation.status else {
            XCTFail("An old server observation plus expired route validity must remain stale.")
            return
        }
        XCTAssertTrue(reasons.contains { reason in
            guard case .serverObservationTooOld(let age, let maximumAge) = reason else { return false }
            return abs(age - 120) < 2 && maximumAge == 60
        })
        XCTAssertTrue(reasons.contains(.routeValidityExpired(validUntil)))
        XCTAssertEqual(observation.package?.mode, .rail)
        XCTAssertEqual(observation.package?.provenance, .serverCanonical)
    }

    func testWallClockRollbackCannotRelabelExpiredRouteFresh() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let now = currentWholeSecond()
        let clock = LockedCanonicalRouteTestClock(now)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-clock-regression",
            userID: "user-clock-regression",
            loadID: "load-clock-regression"
        )
        let envelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "clock-regression-route",
            generatedAt: now.addingTimeInterval(-150),
            issuedAt: now.addingTimeInterval(-120),
            validUntil: now.addingTimeInterval(-10)
        )
        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now.addingTimeInterval(-30),
            storedAt: now.addingTimeInterval(-20)
        )
        clock.advanceUptime(by: 120)
        clock.set(now.addingTimeInterval(-100))

        let rolledBackObservation = try await store.observe(
            scope: scope,
            policy: try CanonicalRouteFreshnessPolicy(
                maximumServerObservationAge: 60,
                allowedClockSkew: 5
            )
        )

        guard case .stale(let reasons) = rolledBackObservation.status else {
            XCTFail("Wall-clock rollback must not mark an elapsed signed route fresh.")
            return
        }
        XCTAssertTrue(reasons.contains { reason in
            guard case .serverObservationTooOld(let age, let maximumAge) = reason else { return false }
            return abs(age - 120) < 0.001 && maximumAge == 60
        })
        XCTAssertTrue(reasons.contains(.routeValidityExpired(now.addingTimeInterval(-10))))
        XCTAssertEqual(rolledBackObservation.observedAt, now)
    }

    func testWallClockForwardJumpDoesNotPrematurelyExpireRoute() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let now = currentWholeSecond()
        let clock = LockedCanonicalRouteTestClock(now, uptime: 500)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-forward-jump",
            userID: "user-forward-jump",
            loadID: "load-forward-jump"
        )
        let envelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "forward-jump-route",
            generatedAt: now.addingTimeInterval(-30),
            issuedAt: now,
            validUntil: now.addingTimeInterval(60)
        )
        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now,
            storedAt: now
        )

        clock.set(now.addingTimeInterval(365 * 24 * 60 * 60))
        clock.advanceUptime(by: 30)

        let observation = try await store.observe(
            scope: scope,
            policy: try CanonicalRouteFreshnessPolicy(
                maximumServerObservationAge: 60,
                allowedClockSkew: 0
            )
        )
        XCTAssertEqual(observation.status, .fresh)
        XCTAssertEqual(observation.observedAt, now.addingTimeInterval(30))
    }

    func testUptimeRegressionFailsFreshnessClosedAndCannotSelfRecover() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let now = currentWholeSecond()
        let clock = LockedCanonicalRouteTestClock(now, uptime: 1_000)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-reboot",
            userID: "user-reboot",
            loadID: "load-reboot"
        )
        let envelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "pre-reboot-route",
            generatedAt: now.addingTimeInterval(-30),
            issuedAt: now,
            validUntil: now.addingTimeInterval(3_600)
        )
        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now,
            storedAt: now
        )
        let policy = try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)

        clock.advanceUptime(by: 10)
        let beforeRegression = try await store.observe(scope: scope, policy: policy)
        XCTAssertEqual(beforeRegression.status, .fresh)

        clock.setUptime(5)
        let afterRegression = try await store.observe(scope: scope, policy: policy)
        guard case .stale(let regressionReasons) = afterRegression.status else {
            XCTFail("Uptime regression must invalidate route freshness.")
            return
        }
        XCTAssertTrue(regressionReasons.contains(
            .trustedTimeUnavailable(
                .monotonicUptimeRegressed(previousUptime: 1_010, observedUptime: 5)
            )
        ))

        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now,
            storedAt: now
        )
        let afterSignedByteReplay = try await store.observe(scope: scope, policy: policy)
        XCTAssertEqual(afterSignedByteReplay.status, afterRegression.status)

        // Once reset evidence is seen, merely surpassing the old uptime later
        // cannot revive the anchor. Only a newer signed response may do that.
        clock.setUptime(2_000)
        let afterSurpassingOldUptime = try await store.observe(scope: scope, policy: policy)
        XCTAssertEqual(afterSurpassingOldUptime.status, afterRegression.status)
    }

    func testNewerSignedResponseReanchorsAfterUptimeRegression() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let now = currentWholeSecond()
        let clock = LockedCanonicalRouteTestClock(now, uptime: 1_000)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-reanchor",
            userID: "user-reanchor",
            loadID: "load-reanchor"
        )
        let original = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "original-route",
            generatedAt: now.addingTimeInterval(-30),
            issuedAt: now,
            validUntil: now.addingTimeInterval(3_600)
        )
        _ = try await store.store(
            signedEnvelope: original,
            expectedScope: scope,
            receivedAt: now,
            storedAt: now
        )
        clock.setUptime(2)
        let policy = try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)
        let afterRegression = try await store.observe(scope: scope, policy: policy)
        guard case .stale = afterRegression.status else {
            XCTFail("The reboot simulation must invalidate the original anchor.")
            return
        }

        let refreshed = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "reanchored-route",
            generatedAt: now.addingTimeInterval(10),
            issuedAt: now.addingTimeInterval(20),
            validUntil: now.addingTimeInterval(3_600)
        )
        _ = try await store.store(
            signedEnvelope: refreshed,
            expectedScope: scope,
            receivedAt: now.addingTimeInterval(-10_000),
            storedAt: now.addingTimeInterval(10_000)
        )

        let reanchored = try await store.observe(scope: scope, policy: policy)
        XCTAssertEqual(reanchored.status, .fresh)
        XCTAssertEqual(reanchored.package?.routeID, "reanchored-route")
        XCTAssertEqual(reanchored.observedAt, now.addingTimeInterval(20))
    }

    func testSignedValidityExpiresAtMonotonicBoundary() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let now = currentWholeSecond()
        let clock = LockedCanonicalRouteTestClock(now, uptime: 100)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-expiry",
            userID: "user-expiry",
            loadID: "load-expiry"
        )
        let validUntil = now.addingTimeInterval(30)
        let envelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "expiry-boundary-route",
            generatedAt: now.addingTimeInterval(-10),
            issuedAt: now,
            validUntil: validUntil
        )
        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now,
            storedAt: now
        )
        let policy = try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)

        clock.advanceUptime(by: 30)
        let atValidityBoundary = try await store.observe(scope: scope, policy: policy)
        XCTAssertEqual(atValidityBoundary.status, .fresh)

        clock.advanceUptime(by: 0.001)
        let expired = try await store.observe(scope: scope, policy: policy)
        guard case .stale(let reasons) = expired.status else {
            XCTFail("Signed validity must expire once monotonic time crosses the boundary.")
            return
        }
        XCTAssertTrue(reasons.contains(.routeValidityExpired(validUntil)))
    }

    func testTrustedAnchorIsNotUnsafelyRestoredIntoNewProcessSession() throws {
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-session",
            userID: "user-session",
            loadID: "load-session"
        )
        let principal = CanonicalRoutePrincipal(scope: scope)
        let firstSessionUptime = LockedCanonicalRouteTestClock(Date(), uptime: 100)
        let firstSession = CanonicalRouteTrustedClock(
            monotonicUptime: { firstSessionUptime.uptime() }
        )
        _ = try firstSession.establishAuthenticatedAnchor(
            for: principal,
            signedServerTime: currentWholeSecond()
        )
        guard case .trusted = firstSession.reading(for: principal) else {
            XCTFail("Authenticated receipt must establish current-session trust.")
            return
        }

        let laterSessionUptime = LockedCanonicalRouteTestClock(Date(), uptime: 10_000)
        let laterSession = CanonicalRouteTrustedClock(
            monotonicUptime: { laterSessionUptime.uptime() }
        )
        XCTAssertEqual(
            laterSession.reading(for: principal),
            .unavailable(.authenticatedAnchorUnavailable)
        )
    }

    func testInvalidSignatureAndSignedScopeMismatchAreRejectedBeforePersistence() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let store = try CanonicalRoutePackageStore(rootDirectory: root, verifier: signing.verifier)
        let signedScope = try CanonicalRouteScope(
            tenantID: "tenant-signed",
            userID: "user-signed",
            loadID: "load-signed"
        )
        let otherScope = try CanonicalRouteScope(
            tenantID: "tenant-other",
            userID: "user-signed",
            loadID: "load-signed"
        )
        let now = currentWholeSecond()
        let validEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: signedScope,
            routeID: "signed-route",
            generatedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600)
        )
        var invalidSignature = validEnvelope.signature
        invalidSignature[invalidSignature.startIndex] ^= 0x01
        let invalidEnvelope = try CanonicalRouteSignedEnvelope(
            keyID: validEnvelope.keyID,
            algorithm: validEnvelope.algorithm,
            payload: validEnvelope.payload,
            signature: invalidSignature
        )

        do {
            _ = try await store.store(
                signedEnvelope: invalidEnvelope,
                expectedScope: signedScope,
                receivedAt: now,
                storedAt: now
            )
            XCTFail("A forged route.plan signature must never reach scoped persistence.")
        } catch {
            XCTAssertEqual(error as? CanonicalRouteStoreError, .invalidSignature)
        }

        do {
            _ = try await store.store(
                signedEnvelope: validEnvelope,
                expectedScope: otherScope,
                receivedAt: now,
                storedAt: now
            )
            XCTFail("Signed tenant/user/load claims must match the requested cache scope.")
        } catch {
            XCTAssertEqual(error as? CanonicalRouteStoreError, .signedClaimMismatch)
        }

        let policy = try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)
        let signedObservation = try await store.observe(scope: signedScope, policy: policy)
        let otherObservation = try await store.observe(scope: otherScope, policy: policy)
        XCTAssertEqual(signedObservation.status, .missing)
        XCTAssertEqual(otherObservation.status, .missing)
    }

    func testSignedPayloadRejectsSegmentModeMismatch() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let store = try CanonicalRoutePackageStore(rootDirectory: root, verifier: signing.verifier)
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-mode",
            userID: "user-mode",
            loadID: "load-mode"
        )
        let now = currentWholeSecond()
        let validEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "mode-route",
            generatedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600)
        )
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validEnvelope.payload) as? [String: Any]
        )
        payload["mode"] = OfflineRouteMode.vessel.rawValue
        let mismatchedPayload = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let mismatchedEnvelope = try CanonicalRouteSignedEnvelope(
            keyID: keyID,
            algorithm: .ed25519,
            payload: mismatchedPayload,
            signature: try signing.privateKey.signature(for: mismatchedPayload)
        )

        do {
            _ = try await store.store(
                signedEnvelope: mismatchedEnvelope,
                expectedScope: scope,
                receivedAt: now,
                storedAt: now
            )
            XCTFail("A signed vessel package cannot carry rail geometry segments.")
        } catch {
            XCTAssertEqual(error as? CanonicalRouteStoreError, .decodingFailed)
        }
    }

    func testGenerationTimelineAndValidityHorizonAreEnforced() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let clock = LockedCanonicalRouteTestClock(currentWholeSecond())
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            maximumFutureTimestampSkew: 30,
            maximumRouteValidityHorizon: 3_600,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-time",
            userID: "user-time",
            loadID: "load-time"
        )
        let now = currentWholeSecond()
        clock.set(now)
        let baselineEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "baseline-time-route",
            generatedAt: now.addingTimeInterval(-30),
            issuedAt: now,
            validUntil: now.addingTimeInterval(300)
        )
        _ = try await store.store(
            signedEnvelope: baselineEnvelope,
            expectedScope: scope,
            receivedAt: now,
            storedAt: now
        )
        let futureGeneratedEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "future-route",
            generatedAt: now.addingTimeInterval(120),
            validUntil: now.addingTimeInterval(300)
        )

        do {
            _ = try await store.store(
                signedEnvelope: futureGeneratedEnvelope,
                expectedScope: scope,
                receivedAt: now,
                storedAt: now
            )
            XCTFail("Generation cannot lead the authenticated server observation beyond skew.")
        } catch let CanonicalRouteStoreError.invalidPackage(message) {
            XCTAssertTrue(message.contains("future"))
        } catch {
            XCTFail("Expected timeline validation, received \(error).")
        }

        let validityScope = try CanonicalRouteScope(
            tenantID: "tenant-time",
            userID: "user-time",
            loadID: "load-validity-horizon"
        )
        let excessiveValidityEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: validityScope,
            routeID: "long-validity-route",
            generatedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(7_200)
        )
        do {
            _ = try await store.store(
                signedEnvelope: excessiveValidityEnvelope,
                expectedScope: validityScope,
                receivedAt: now,
                storedAt: now
            )
            XCTFail("Signed validity must remain within the configured safety horizon.")
        } catch let CanonicalRouteStoreError.invalidPackage(message) {
            XCTAssertTrue(message.contains("safety horizon"))
        } catch {
            XCTFail("Expected validity-horizon validation, received \(error).")
        }
    }

    func testFutureSkewCannotStackAndUpperBoundPackageRoundTrips() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let clock = LockedCanonicalRouteTestClock(Date(), uptime: 100)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            maximumFutureTimestampSkew: 10,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let now = Date()
        clock.set(now)
        let stackedScope = try CanonicalRouteScope(
            tenantID: "tenant-stacked-skew",
            userID: "user-stacked-skew",
            loadID: "load-stacked-skew"
        )
        let stackedBaseline = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: stackedScope,
            routeID: "stacked-baseline-route",
            generatedAt: now.addingTimeInterval(-10),
            issuedAt: now,
            validUntil: now.addingTimeInterval(300),
            preservesFractionalSeconds: true
        )
        _ = try await store.store(
            signedEnvelope: stackedBaseline,
            expectedScope: stackedScope,
            receivedAt: now,
            storedAt: now
        )
        let stackedEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: stackedScope,
            routeID: "stacked-skew-route",
            generatedAt: now.addingTimeInterval(15),
            issuedAt: now.addingTimeInterval(15),
            validUntil: now.addingTimeInterval(300),
            preservesFractionalSeconds: true
        )

        do {
            _ = try await store.store(
                signedEnvelope: stackedEnvelope,
                expectedScope: stackedScope,
                receivedAt: now.addingTimeInterval(8),
                storedAt: now.addingTimeInterval(8)
            )
            XCTFail("Receipt skew must not stack with signed issuance skew.")
        } catch let CanonicalRouteStoreError.invalidPackage(message) {
            XCTAssertTrue(message.contains("future"))
        } catch {
            XCTFail("Expected direct signed-time validation, received \(error).")
        }

        let upperBoundScope = try CanonicalRouteScope(
            tenantID: "tenant-upper-skew",
            userID: "user-upper-skew",
            loadID: "load-upper-skew"
        )
        let upperBoundBaseline = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: upperBoundScope,
            routeID: "upper-baseline-route",
            generatedAt: now.addingTimeInterval(-10),
            issuedAt: now,
            validUntil: now.addingTimeInterval(300),
            preservesFractionalSeconds: true
        )
        _ = try await store.store(
            signedEnvelope: upperBoundBaseline,
            expectedScope: upperBoundScope,
            receivedAt: now,
            storedAt: now
        )
        let upperBoundEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: upperBoundScope,
            routeID: "upper-skew-route",
            generatedAt: now.addingTimeInterval(9),
            issuedAt: now.addingTimeInterval(9),
            validUntil: now.addingTimeInterval(300),
            preservesFractionalSeconds: true
        )
        _ = try await store.store(
            signedEnvelope: upperBoundEnvelope,
            expectedScope: upperBoundScope,
            receivedAt: now.addingTimeInterval(8),
            storedAt: now.addingTimeInterval(8)
        )

        let observation = try await store.observe(
            scope: upperBoundScope,
            policy: try CanonicalRouteFreshnessPolicy(
                maximumServerObservationAge: 300,
                allowedClockSkew: 10
            )
        )
        XCTAssertEqual(observation.status, .fresh)
        XCTAssertEqual(observation.package?.routeID, "upper-skew-route")
        XCTAssertEqual(
            try XCTUnwrap(observation.storedAt).timeIntervalSince1970,
            now.addingTimeInterval(8).timeIntervalSince1970,
            accuracy: 0.000_001
        )
    }

    func testPersistedPackageIsReverifiedAndInvalidNestedDataStillFailsDecode() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let store = try CanonicalRoutePackageStore(rootDirectory: root, verifier: signing.verifier)
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-tampered",
            userID: "user-tampered",
            loadID: "load-tampered"
        )
        let now = currentWholeSecond()
        let envelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "tampered-route",
            generatedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600)
        )
        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now.addingTimeInterval(-30),
            storedAt: now.addingTimeInterval(-20)
        )
        let fileURL = cachedFileURL(root: root, scope: scope)
        var persisted = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        var storedSignedEnvelope = try XCTUnwrap(persisted["signedEnvelope"] as? [String: Any])
        let originalPayload = try XCTUnwrap(
            Data(base64Encoded: try XCTUnwrap(storedSignedEnvelope["payload"] as? String))
        )
        var signedPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: originalPayload) as? [String: Any]
        )
        signedPayload["routeID"] = "locally-substituted-route"
        let substitutedPayload = try JSONSerialization.data(
            withJSONObject: signedPayload,
            options: [.sortedKeys]
        )
        storedSignedEnvelope["payload"] = substitutedPayload.base64EncodedString()
        persisted["signedEnvelope"] = storedSignedEnvelope
        try JSONSerialization.data(withJSONObject: persisted, options: [.sortedKeys])
            .write(to: fileURL, options: .atomic)

        do {
            _ = try await store.observe(
                scope: scope,
                policy: try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)
            )
            XCTFail("Persisted cleartext claims must still match the reverified signed payload.")
        } catch {
            XCTAssertEqual(error as? CanonicalRouteStoreError, .invalidSignature)
        }

        try await store.purge(scope: scope)
        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now.addingTimeInterval(-30),
            storedAt: now.addingTimeInterval(-20)
        )
        persisted = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        storedSignedEnvelope = try XCTUnwrap(persisted["signedEnvelope"] as? [String: Any])
        let restoredPayload = try XCTUnwrap(
            Data(base64Encoded: try XCTUnwrap(storedSignedEnvelope["payload"] as? String))
        )
        signedPayload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: restoredPayload) as? [String: Any]
        )
        var summary = try XCTUnwrap(signedPayload["summary"] as? [String: Any])
        summary["distanceMeters"] = -1
        signedPayload["summary"] = summary
        let invalidNestedPayload = try JSONSerialization.data(
            withJSONObject: signedPayload,
            options: [.sortedKeys]
        )
        storedSignedEnvelope["payload"] = invalidNestedPayload.base64EncodedString()
        storedSignedEnvelope["signature"] = try signing.privateKey
            .signature(for: invalidNestedPayload)
            .base64EncodedString()
        persisted["signedEnvelope"] = storedSignedEnvelope
        try JSONSerialization.data(withJSONObject: persisted, options: [.sortedKeys])
            .write(to: fileURL, options: .atomic)

        do {
            _ = try await store.observe(
                scope: scope,
                policy: try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)
            )
            XCTFail("Invalid nested summary data must not bypass validated decoding.")
        } catch {
            XCTAssertEqual(error as? CanonicalRouteStoreError, .decodingFailed)
        }
    }

    func testReplayedSignedBytesCannotRefreshFreshnessAndStaleOrConflictingRoutesAreRejected() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let clock = LockedCanonicalRouteTestClock(currentWholeSecond(), uptime: 100)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-replay",
            userID: "user-replay",
            loadID: "load-replay"
        )
        let now = currentWholeSecond()
        let currentEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "current-signed-route",
            generatedAt: now.addingTimeInterval(-180),
            issuedAt: now.addingTimeInterval(-120),
            validUntil: now.addingTimeInterval(3_600)
        )
        _ = try await store.store(
            signedEnvelope: currentEnvelope,
            expectedScope: scope,
            receivedAt: now.addingTimeInterval(-60),
            storedAt: now.addingTimeInterval(-50)
        )
        clock.advanceUptime(by: 120)

        // Receiving the same signed bytes again is idempotent, but the local
        // receipt must not make its old signed issuance appear current.
        _ = try await store.store(
            signedEnvelope: currentEnvelope,
            expectedScope: scope,
            receivedAt: now,
            storedAt: now
        )
        let freshness = try CanonicalRouteFreshnessPolicy(
            maximumServerObservationAge: 60,
            allowedClockSkew: 0
        )
        let replayedObservation = try await store.observe(scope: scope, policy: freshness)
        guard case .stale(let reasons) = replayedObservation.status else {
            XCTFail("A new local receipt must not refresh old signed route bytes.")
            return
        }
        XCTAssertTrue(reasons.contains { reason in
            guard case .serverObservationTooOld(let age, let maximumAge) = reason else { return false }
            return abs(age - 120) < 2 && maximumAge == 60
        })

        let olderEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "older-signed-route",
            generatedAt: now.addingTimeInterval(-240),
            issuedAt: now.addingTimeInterval(-180),
            validUntil: now.addingTimeInterval(3_600)
        )
        do {
            _ = try await store.store(
                signedEnvelope: olderEnvelope,
                expectedScope: scope,
                receivedAt: now,
                storedAt: now
            )
            XCTFail("An older valid server signature must not replace a newer scoped route.")
        } catch {
            XCTAssertEqual(error as? CanonicalRouteStoreError, .staleSignedRouteReplay)
        }

        let conflictingEnvelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "conflicting-same-issuance-route",
            generatedAt: now.addingTimeInterval(-180),
            issuedAt: now.addingTimeInterval(-120),
            validUntil: now.addingTimeInterval(3_600)
        )
        do {
            _ = try await store.store(
                signedEnvelope: conflictingEnvelope,
                expectedScope: scope,
                receivedAt: now,
                storedAt: now
            )
            XCTFail("Equal issuance with conflicting signed bytes must be rejected.")
        } catch {
            XCTAssertEqual(error as? CanonicalRouteStoreError, .staleSignedRouteReplay)
        }

        let retained = try await store.observe(
            scope: scope,
            policy: try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)
        )
        XCTAssertEqual(retained.package?.routeID, "current-signed-route")
    }

    func testScopedAndPrincipalWidePurgeRemoveOnlyIntendedPackages() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let clock = LockedCanonicalRouteTestClock(currentWholeSecond(), uptime: 100)
        let trustedClock = CanonicalRouteTrustedClock(monotonicUptime: { clock.uptime() })
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            trustedClock: trustedClock,
            currentTime: { clock.now() }
        )
        let firstScope = try CanonicalRouteScope(
            tenantID: "tenant-purge",
            userID: "user-a",
            loadID: "load-a"
        )
        let secondScope = try CanonicalRouteScope(
            tenantID: "tenant-purge",
            userID: "user-b",
            loadID: "load-b"
        )
        let now = currentWholeSecond()
        for (index, scope) in [firstScope, secondScope].enumerated() {
            let envelope = try makeSignedEnvelope(
                signingKey: signing.privateKey,
                scope: scope,
                routeID: "purge-route-\(index)",
                generatedAt: now.addingTimeInterval(-60),
                validUntil: now.addingTimeInterval(3_600)
            )
            _ = try await store.store(
                signedEnvelope: envelope,
                expectedScope: scope,
                receivedAt: now,
                storedAt: now
            )
        }
        let policy = try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)

        try await store.purge(scope: firstScope)

        let purgedFirst = try await store.observe(scope: firstScope, policy: policy)
        let retainedSecond = try await store.observe(scope: secondScope, policy: policy)
        XCTAssertEqual(purgedFirst.status, .missing)
        XCTAssertEqual(retainedSecond.status, .fresh)

        try await store.purgeAllCachedRoutes()

        let purgedSecond = try await store.observe(scope: secondScope, policy: policy)
        XCTAssertEqual(purgedSecond.status, .missing)
        XCTAssertEqual(
            trustedClock.reading(for: CanonicalRoutePrincipal(scope: firstScope)),
            .unavailable(.authenticatedAnchorUnavailable)
        )
        XCTAssertEqual(
            trustedClock.reading(for: CanonicalRoutePrincipal(scope: secondScope)),
            .unavailable(.authenticatedAnchorUnavailable)
        )
    }

    func testOversizePayloadGeometryAndStringInputsAreRejectedAtTheirBoundaries() throws {
        let oversizedPayload = Data(repeating: 0x41, count: 8 * 1_024 * 1_024 + 1)
        XCTAssertThrowsError(
            try CanonicalRouteSignedEnvelope(
                keyID: keyID,
                algorithm: .ed25519,
                payload: oversizedPayload,
                signature: Data(repeating: 0, count: 64)
            )
        ) { error in
            guard case CanonicalRouteStoreError.invalidPackage(let message) = error else {
                XCTFail("Expected signed-payload size rejection, received \(error).")
                return
            }
            XCTAssertTrue(message.contains("safe byte limit"))
        }

        let coordinate = try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698)
        XCTAssertThrowsError(
            try CanonicalRouteGeometrySegment(
                id: "oversize-geometry",
                sequence: 0,
                mode: .rail,
                coordinates: Array(repeating: coordinate, count: 10_001)
            )
        ) { error in
            guard case CanonicalRouteStoreError.invalidPackage(let message) = error else {
                XCTFail("Expected geometry limit rejection, received \(error).")
                return
            }
            XCTAssertTrue(message.contains("too many coordinates"))
        }

        XCTAssertThrowsError(
            try CanonicalRouteGeometrySegment(
                id: String(repeating: "i", count: 257),
                sequence: 0,
                mode: .rail,
                coordinates: [coordinate, coordinate]
            )
        ) { error in
            guard case CanonicalRouteStoreError.invalidPackage(let message) = error else {
                XCTFail("Expected identifier limit rejection, received \(error).")
                return
            }
            XCTAssertTrue(message.contains("identifier is too long"))
        }

        XCTAssertThrowsError(
            try CanonicalRouteInstruction(
                sequence: 0,
                text: String(repeating: "t", count: 4_097),
                coordinate: coordinate
            )
        ) { error in
            guard case CanonicalRouteStoreError.invalidPackage(let message) = error else {
                XCTFail("Expected instruction-text limit rejection, received \(error).")
                return
            }
            XCTAssertTrue(message.contains("text is too long"))
        }
    }

    func testNearLimitSignedPayloadStoresAndObservesThroughCompactEnvelope() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let store = try CanonicalRoutePackageStore(rootDirectory: root, verifier: signing.verifier)
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-envelope-limit",
            userID: "user-envelope-limit",
            loadID: "load-envelope-limit"
        )
        let now = currentWholeSecond()
        let origin = try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698)
        let destination = try OfflineGeoCoordinate(latitude: 32.7767, longitude: -96.7970)
        let repeatedText = String(repeating: "x", count: 4_000)
        let instructions = try (0 ..< 2_000).map {
            try CanonicalRouteInstruction(sequence: $0, text: repeatedText, coordinate: nil)
        }
        let payload = try CanonicalRouteSignedPayload(
            issuer: issuer,
            audience: audience,
            scope: scope,
            routeID: "large-persisted-envelope",
            serverRevision: "large-persisted-envelope-revision",
            mode: .rail,
            issuedAt: now.addingTimeInterval(-30),
            generatedAt: now.addingTimeInterval(-60),
            validUntil: now.addingTimeInterval(3_600),
            summary: try CanonicalRouteSummary(distanceMeters: 385_000, durationSeconds: 18_000),
            segments: [
                try CanonicalRouteGeometrySegment(
                    id: "large-envelope-segment",
                    sequence: 0,
                    mode: .rail,
                    coordinates: [origin, destination]
                )
            ],
            instructions: instructions
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        XCTAssertGreaterThan(payloadData.count, 7 * 1_024 * 1_024)
        XCTAssertLessThanOrEqual(payloadData.count, 8 * 1_024 * 1_024)
        let envelope = try CanonicalRouteSignedEnvelope(
            keyID: keyID,
            algorithm: .ed25519,
            payload: payloadData,
            signature: try signing.privateKey.signature(for: payloadData)
        )

        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now,
            storedAt: now
        )

        let storedFileSize = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: cachedFileURL(root: root, scope: scope).path)[.size]
                as? NSNumber
        ).intValue
        XCTAssertLessThanOrEqual(storedFileSize, 12 * 1_024 * 1_024)

        let observation = try await store.observe(
            scope: scope,
            policy: try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)
        )
        XCTAssertEqual(observation.status, .fresh)
        XCTAssertEqual(observation.package?.routeID, "large-persisted-envelope")
        XCTAssertEqual(observation.package?.instructions.count, 2_000)
        XCTAssertEqual(observation.package?.signedEnvelope, envelope)
    }

    func testFractionalSignedIssuanceRoundTripsWithoutUnsignedTimestampDrift() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let store = try CanonicalRoutePackageStore(rootDirectory: root, verifier: signing.verifier)
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-fractional-issued-at",
            userID: "user-fractional-issued-at",
            loadID: "load-fractional-issued-at"
        )
        let now = currentWholeSecond()
        let issuedAt = now.addingTimeInterval(-30.123)
        let envelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "fractional-issued-at-route",
            generatedAt: now.addingTimeInterval(-60.456),
            issuedAt: issuedAt,
            validUntil: now.addingTimeInterval(3_600),
            preservesFractionalSeconds: true
        )

        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: now.addingTimeInterval(-20),
            storedAt: now.addingTimeInterval(-10)
        )

        let observation = try await store.observe(
            scope: scope,
            policy: try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)
        )
        XCTAssertEqual(observation.status, .fresh)
        XCTAssertEqual(
            try XCTUnwrap(observation.package).issuedAt.timeIntervalSince1970,
            issuedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(observation.lastServerObservedAt, observation.package?.issuedAt)
    }

    func testZeroSkewFractionalStoreReceiptRoundTripsExactly() async throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let store = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier,
            maximumFutureTimestampSkew: 0
        )
        let scope = try CanonicalRouteScope(
            tenantID: "tenant-fractional-store",
            userID: "user-fractional-store",
            loadID: "load-fractional-store"
        )
        let now = currentWholeSecond()
        let envelope = try makeSignedEnvelope(
            signingKey: signing.privateKey,
            scope: scope,
            routeID: "fractional-store-route",
            generatedAt: now.addingTimeInterval(-31.987),
            issuedAt: now.addingTimeInterval(-30.789),
            validUntil: now.addingTimeInterval(3_600),
            preservesFractionalSeconds: true
        )
        let verified = try signing.verifier.verify(envelope, expectedScope: scope)

        _ = try await store.store(
            signedEnvelope: envelope,
            expectedScope: scope,
            receivedAt: verified.issuedAt,
            storedAt: verified.issuedAt
        )

        let observation = try await store.observe(
            scope: scope,
            policy: try CanonicalRouteFreshnessPolicy(maximumServerObservationAge: 300)
        )
        XCTAssertEqual(observation.status, .fresh)
        XCTAssertEqual(
            try XCTUnwrap(observation.storedAt).timeIntervalSince1970,
            verified.issuedAt.timeIntervalSince1970,
            accuracy: 0.000_001
        )
    }

    func testSecondStoreForSameRootFailsClosed() throws {
        let root = temporaryStoreRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let signing = try makeSigningFixture()
        let firstStore = try CanonicalRoutePackageStore(
            rootDirectory: root,
            verifier: signing.verifier
        )

        XCTAssertThrowsError(
            try CanonicalRoutePackageStore(rootDirectory: root, verifier: signing.verifier)
        ) { error in
            guard case CanonicalRouteStoreError.invalidPolicy = error else {
                XCTFail("Expected single-writer root rejection, received \(error).")
                return
            }
        }
        withExtendedLifetime(firstStore) {}
    }

    func testInvalidFutureSkewPolicyThrowsInsteadOfCrashing() throws {
        let signing = try makeSigningFixture()
        XCTAssertThrowsError(
            try CanonicalRoutePackageStore(
                rootDirectory: temporaryStoreRoot(),
                verifier: signing.verifier,
                maximumFutureTimestampSkew: -Double.infinity
            )
        ) { error in
            guard case CanonicalRouteStoreError.invalidPolicy = error else {
                XCTFail("Expected invalid policy, received \(error).")
                return
            }
        }
    }

    private struct SigningFixture {
        let privateKey: Curve25519.Signing.PrivateKey
        let verifier: CanonicalRoutePlanVerifier
    }

    private func makeSigningFixture() throws -> SigningFixture {
        let privateKey = Curve25519.Signing.PrivateKey()
        let verificationKey = try CanonicalRouteVerificationKey(
            keyID: keyID,
            ed25519RawRepresentation: privateKey.publicKey.rawRepresentation
        )
        let verifier = try CanonicalRoutePlanVerifier(
            expectedIssuer: issuer,
            expectedAudience: audience,
            keys: [verificationKey]
        )
        return SigningFixture(privateKey: privateKey, verifier: verifier)
    }

    private func makeSignedEnvelope(
        signingKey: Curve25519.Signing.PrivateKey,
        scope: CanonicalRouteScope,
        routeID: String,
        mode: OfflineRouteMode = .rail,
        generatedAt: Date,
        issuedAt: Date? = nil,
        validUntil: Date?,
        preservesFractionalSeconds: Bool = false
    ) throws -> CanonicalRouteSignedEnvelope {
        let origin = try OfflineGeoCoordinate(latitude: 29.7604, longitude: -95.3698)
        let destination = try OfflineGeoCoordinate(latitude: 32.7767, longitude: -96.7970)
        let payload = try CanonicalRouteSignedPayload(
            issuer: issuer,
            audience: audience,
            scope: scope,
            routeID: routeID,
            serverRevision: "revision-\(routeID)",
            mode: mode,
            issuedAt: issuedAt ?? generatedAt,
            generatedAt: generatedAt,
            validUntil: validUntil,
            summary: try CanonicalRouteSummary(distanceMeters: 385_000, durationSeconds: 18_000),
            segments: [
                try CanonicalRouteGeometrySegment(
                    id: "segment-\(routeID)",
                    sequence: 0,
                    mode: mode,
                    coordinates: [origin, destination]
                )
            ],
            instructions: [
                try CanonicalRouteInstruction(
                    sequence: 0,
                    text: "Follow the signed server-canonical segment.",
                    coordinate: origin
                )
            ]
        )
        let encoder = JSONEncoder()
        if preservesFractionalSeconds {
            encoder.dateEncodingStrategy = .custom { date, encoder in
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                var container = encoder.singleValueContainer()
                try container.encode(formatter.string(from: date))
            }
        } else {
            encoder.dateEncodingStrategy = .iso8601
        }
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        return try CanonicalRouteSignedEnvelope(
            keyID: keyID,
            algorithm: .ed25519,
            payload: payloadData,
            signature: try signingKey.signature(for: payloadData)
        )
    }

    private func currentWholeSecond() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }

    private func temporaryStoreRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EusoTripOfflineTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func cachedFileURL(root: URL, scope: CanonicalRouteScope) -> URL {
        root
            .appendingPathComponent("canonical-routes", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
            .appendingPathComponent("tenant_\(encoded(scope.tenantID))", isDirectory: true)
            .appendingPathComponent("user_\(encoded(scope.userID))", isDirectory: true)
            .appendingPathComponent("load_\(encoded(scope.loadID))", isDirectory: false)
            .appendingPathExtension("json")
    }

    private func encoded(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
