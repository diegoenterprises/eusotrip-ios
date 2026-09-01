//
//  CanonicalRouteTrustedClock.swift
//  EusoTrip
//
//  Receipt-anchors authenticated server time to monotonic uptime. The anchor
//  is deliberately process-memory-only: ProcessInfo.systemUptime can detect a
//  regression while this process is alive, but cannot by itself prove that a
//  later process is still in the same boot after uptime has surpassed an old
//  persisted value. A relaunch or reboot therefore needs newer signed server
//  evidence before cached Rail/Vessel route freshness can be trusted again.
//

import Foundation

struct CanonicalRoutePrincipal: Hashable, Sendable {
    let tenantID: String
    let userID: String

    init(scope: CanonicalRouteScope) {
        tenantID = scope.tenantID
        userID = scope.userID
    }
}

enum CanonicalRouteTrustedTimeFailure: Equatable, Sendable {
    case authenticatedAnchorUnavailable
    case invalidMonotonicUptime
    case monotonicUptimeRegressed(previousUptime: TimeInterval, observedUptime: TimeInterval)
}

enum CanonicalRouteTrustedTimeReading: Equatable, Sendable {
    case trusted(Date)
    case unavailable(CanonicalRouteTrustedTimeFailure)
}

enum CanonicalRouteTrustedClockError: Error, Equatable, Sendable {
    case invalidSignedServerTime
    case invalidMonotonicUptime
}

/// Maintains one current-boot time authority per authenticated principal.
///
/// `signedServerTime` is trusted only after the route envelope signature and
/// scope have been verified by `CanonicalRoutePlanVerifier`. Elapsed time then
/// comes exclusively from monotonic system uptime, so wall-clock rollback or a
/// forward wall-clock jump cannot change route age or validity.
final class CanonicalRouteTrustedClock: @unchecked Sendable {
    private struct Anchor {
        let signedServerTime: Date
        let receiptUptime: TimeInterval
        var latestObservedUptime: TimeInterval
    }

    private enum Entry {
        case active(Anchor)
        case invalidated(CanonicalRouteTrustedTimeFailure)
    }

    private let lock = NSLock()
    private let monotonicUptime: @Sendable () -> TimeInterval
    private var entries: [CanonicalRoutePrincipal: Entry] = [:]

    init(
        monotonicUptime: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.monotonicUptime = monotonicUptime
    }

    /// Accepts a server timestamp only after its enclosing response has been
    /// authenticated and its principal scope verified. Re-anchoring never
    /// moves trusted time backwards within the same valid boot session.
    @discardableResult
    func establishAuthenticatedAnchor(
        for principal: CanonicalRoutePrincipal,
        signedServerTime: Date
    ) throws -> Date {
        guard signedServerTime.timeIntervalSince1970.isFinite else {
            throw CanonicalRouteTrustedClockError.invalidSignedServerTime
        }
        let uptime = monotonicUptime()
        guard Self.isValid(uptime: uptime) else {
            throw CanonicalRouteTrustedClockError.invalidMonotonicUptime
        }

        lock.lock()
        defer { lock.unlock() }

        var effectiveServerTime = signedServerTime
        if case .active(let existing)? = entries[principal],
           uptime >= existing.latestObservedUptime {
            let elapsed = uptime - existing.receiptUptime
            let existingTrustedTime = existing.signedServerTime.addingTimeInterval(elapsed)
            if existingTrustedTime.timeIntervalSince1970.isFinite {
                effectiveServerTime = max(effectiveServerTime, existingTrustedTime)
            }
        }

        entries[principal] = .active(
            Anchor(
                signedServerTime: effectiveServerTime,
                receiptUptime: uptime,
                latestObservedUptime: uptime
            )
        )
        return effectiveServerTime
    }

    func reading(for principal: CanonicalRoutePrincipal) -> CanonicalRouteTrustedTimeReading {
        let uptime = monotonicUptime()

        lock.lock()
        defer { lock.unlock() }

        guard Self.isValid(uptime: uptime) else {
            let failure = CanonicalRouteTrustedTimeFailure.invalidMonotonicUptime
            if entries[principal] != nil {
                entries[principal] = .invalidated(failure)
            }
            return .unavailable(failure)
        }
        guard let entry = entries[principal] else {
            return .unavailable(.authenticatedAnchorUnavailable)
        }
        switch entry {
        case .invalidated(let failure):
            return .unavailable(failure)
        case .active(var anchor):
            let previousUptime = max(anchor.receiptUptime, anchor.latestObservedUptime)
            guard uptime >= previousUptime else {
                let failure = CanonicalRouteTrustedTimeFailure.monotonicUptimeRegressed(
                    previousUptime: previousUptime,
                    observedUptime: uptime
                )
                entries[principal] = .invalidated(failure)
                return .unavailable(failure)
            }
            let trustedTime = anchor.signedServerTime.addingTimeInterval(
                uptime - anchor.receiptUptime
            )
            guard trustedTime.timeIntervalSince1970.isFinite else {
                let failure = CanonicalRouteTrustedTimeFailure.invalidMonotonicUptime
                entries[principal] = .invalidated(failure)
                return .unavailable(failure)
            }
            anchor.latestObservedUptime = uptime
            entries[principal] = .active(anchor)
            return .trusted(trustedTime)
        }
    }

    func invalidateAll() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private static func isValid(uptime: TimeInterval) -> Bool {
        uptime.isFinite && uptime >= 0
    }
}
