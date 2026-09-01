//
//  CanonicalRouteTrustedClock.swift
//  EusoTrip
//
//  Receipt-anchors authenticated server time to monotonic uptime. Production
//  persists the authenticated anchor in ThisDeviceOnly Keychain storage and
//  binds it to kern.bootsessionuuid, allowing a force-quit/relaunch in the same
//  boot without trusting wall time. A reboot changes that identifier and still
//  requires newer signed server evidence because elapsed power-off time cannot
//  be proven by an offline app clock.
//

import CryptoKit
import Foundation
import Security
#if canImport(Darwin)
import Darwin
#endif

struct CanonicalRoutePrincipal: Hashable, Sendable {
    let tenantID: String
    let userID: String

    init(scope: CanonicalRouteScope) {
        tenantID = scope.tenantID
        userID = scope.userID
    }
}

enum CanonicalRouteTrustedTimeFailure: Error, Equatable, Sendable {
    case authenticatedAnchorUnavailable
    case bootSessionUnavailable
    case bootSessionChanged
    case persistedAnchorInvalid
    case anchorPersistenceUnavailable
    case invalidMonotonicUptime
    case monotonicUptimeRegressed(previousUptime: TimeInterval, observedUptime: TimeInterval)
}

enum CanonicalRouteTrustedTimeReading: Equatable, Sendable {
    case trusted(Date)
    case unavailable(CanonicalRouteTrustedTimeFailure)
}

enum CanonicalRouteTrustedClockError: Error, Equatable, Sendable {
    case invalidSignedServerTime
    case bootSessionUnavailable
    case anchorPersistenceUnavailable
    case invalidMonotonicUptime
}

protocol CanonicalRouteTrustedAnchorPersistence: Sendable {
    func load(for principal: CanonicalRoutePrincipal) throws -> Data?
    func save(_ data: Data, for principal: CanonicalRoutePrincipal) throws
    func remove(for principal: CanonicalRoutePrincipal) throws
    func removeAll() throws
}

private enum CanonicalRouteTrustedAnchorPersistenceError: Error {
    case keychain(OSStatus)
    case malformedKeychainResult
}

/// The default production persistence is unavailable to other apps, excluded
/// from device migration/backup, and keyed by a one-way principal digest.
private final class KeychainCanonicalRouteTrustedAnchorPersistence:
    CanonicalRouteTrustedAnchorPersistence,
    @unchecked Sendable
{
    private let service = "com.eusorone.EusoTrip.offline-route-trusted-clock.v1"

    func load(for principal: CanonicalRoutePrincipal) throws -> Data? {
        var query = baseQuery(for: principal)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CanonicalRouteTrustedAnchorPersistenceError.keychain(status)
        }
        guard let data = result as? Data else {
            throw CanonicalRouteTrustedAnchorPersistenceError.malformedKeychainResult
        }
        return data
    }

    func save(_ data: Data, for principal: CanonicalRoutePrincipal) throws {
        let query = baseQuery(for: principal)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CanonicalRouteTrustedAnchorPersistenceError.keychain(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CanonicalRouteTrustedAnchorPersistenceError.keychain(addStatus)
        }
    }

    func remove(for principal: CanonicalRoutePrincipal) throws {
        let status = SecItemDelete(baseQuery(for: principal) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CanonicalRouteTrustedAnchorPersistenceError.keychain(status)
        }
    }

    func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CanonicalRouteTrustedAnchorPersistenceError.keychain(status)
        }
    }

    private func baseQuery(for principal: CanonicalRoutePrincipal) -> [String: Any] {
        let identity = "\(principal.tenantID.utf8.count):\(principal.tenantID)\(principal.userID.utf8.count):\(principal.userID)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        let account = digest.map { String(format: "%02x", $0) }.joined()
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// Maintains one current-boot time authority per authenticated principal.
///
/// `signedServerTime` is trusted only after the route envelope signature and
/// scope have been verified by `CanonicalRoutePlanVerifier`. Elapsed time then
/// comes exclusively from monotonic system uptime, so wall-clock rollback or a
/// forward wall-clock jump cannot change route age or validity.
final class CanonicalRouteTrustedClock: @unchecked Sendable {
    private struct PersistedAnchor: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let tenantID: String
        let userID: String
        let bootSessionID: String
        let signedServerTimeEpochSeconds: TimeInterval
        let receiptUptime: TimeInterval

        init(
            principal: CanonicalRoutePrincipal,
            bootSessionID: String,
            signedServerTime: Date,
            receiptUptime: TimeInterval
        ) {
            schemaVersion = Self.currentSchemaVersion
            tenantID = principal.tenantID
            userID = principal.userID
            self.bootSessionID = bootSessionID
            signedServerTimeEpochSeconds = signedServerTime.timeIntervalSince1970
            self.receiptUptime = receiptUptime
        }
    }

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
    private let bootSessionIdentifier: @Sendable () -> String?
    private let persistence: (any CanonicalRouteTrustedAnchorPersistence)?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var entries: [CanonicalRoutePrincipal: Entry] = [:]

    /// Production initializer: process relaunches in the same boot rehydrate a
    /// ThisDeviceOnly anchor. If the kernel boot identity cannot be read, the
    /// cache remains fail-closed instead of falling back to wall time.
    convenience init() {
        self.init(
            monotonicUptime: { ProcessInfo.processInfo.systemUptime },
            bootSessionIdentifier: { Self.currentBootSessionIdentifier() },
            persistence: KeychainCanonicalRouteTrustedAnchorPersistence()
        )
    }

    /// Injection initializer for deterministic tests. Persistence is opt-in,
    /// so a custom uptime closure cannot accidentally consume device state.
    init(
        monotonicUptime: @escaping @Sendable () -> TimeInterval,
        bootSessionIdentifier: @escaping @Sendable () -> String? = { nil },
        persistence: (any CanonicalRouteTrustedAnchorPersistence)? = nil
    ) {
        self.monotonicUptime = monotonicUptime
        self.bootSessionIdentifier = bootSessionIdentifier
        self.persistence = persistence
        encoder.outputFormatting = [.sortedKeys]
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

        let bootSessionID: String?
        if persistence != nil {
            guard let candidate = bootSessionIdentifier(),
                  Self.isValid(bootSessionIdentifier: candidate) else {
                throw CanonicalRouteTrustedClockError.bootSessionUnavailable
            }
            bootSessionID = candidate
        } else {
            bootSessionID = nil
        }

        lock.lock()
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

        if let persistence, let bootSessionID {
            let record = PersistedAnchor(
                principal: principal,
                bootSessionID: bootSessionID,
                signedServerTime: effectiveServerTime,
                receiptUptime: uptime
            )
            do {
                let data = try encoder.encode(record)
                try persistence.save(data, for: principal)
            } catch {
                entries[principal] = .invalidated(.anchorPersistenceUnavailable)
                lock.unlock()
                throw CanonicalRouteTrustedClockError.anchorPersistenceUnavailable
            }
        }
        lock.unlock()
        return effectiveServerTime
    }

    func reading(for principal: CanonicalRoutePrincipal) -> CanonicalRouteTrustedTimeReading {
        let uptime = monotonicUptime()

        lock.lock()
        defer { lock.unlock() }

        guard Self.isValid(uptime: uptime) else {
            let failure = CanonicalRouteTrustedTimeFailure.invalidMonotonicUptime
            entries[principal] = .invalidated(failure)
            try? persistence?.remove(for: principal)
            return .unavailable(failure)
        }

        if entries[principal] == nil, persistence != nil {
            switch restorePersistedAnchor(for: principal, observedUptime: uptime) {
            case .success(let anchor):
                entries[principal] = .active(anchor)
            case .failure(let failure):
                entries[principal] = .invalidated(failure)
            }
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
                try? persistence?.remove(for: principal)
                return .unavailable(failure)
            }
            let trustedTime = anchor.signedServerTime.addingTimeInterval(
                uptime - anchor.receiptUptime
            )
            guard trustedTime.timeIntervalSince1970.isFinite else {
                let failure = CanonicalRouteTrustedTimeFailure.invalidMonotonicUptime
                entries[principal] = .invalidated(failure)
                try? persistence?.remove(for: principal)
                return .unavailable(failure)
            }
            anchor.latestObservedUptime = uptime
            entries[principal] = .active(anchor)
            return .trusted(trustedTime)
        }
    }

    func invalidateAll() throws {
        lock.lock()
        do {
            try persistence?.removeAll()
        } catch {
            lock.unlock()
            throw CanonicalRouteTrustedClockError.anchorPersistenceUnavailable
        }
        entries.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private func restorePersistedAnchor(
        for principal: CanonicalRoutePrincipal,
        observedUptime: TimeInterval
    ) -> Result<Anchor, CanonicalRouteTrustedTimeFailure> {
        guard let persistence else {
            return .failure(.authenticatedAnchorUnavailable)
        }
        guard let currentBootSessionID = bootSessionIdentifier(),
              Self.isValid(bootSessionIdentifier: currentBootSessionID) else {
            return .failure(.bootSessionUnavailable)
        }

        let data: Data
        do {
            guard let persisted = try persistence.load(for: principal) else {
                return .failure(.authenticatedAnchorUnavailable)
            }
            data = persisted
        } catch {
            return .failure(.anchorPersistenceUnavailable)
        }

        let record: PersistedAnchor
        do {
            record = try decoder.decode(PersistedAnchor.self, from: data)
        } catch {
            try? persistence.remove(for: principal)
            return .failure(.persistedAnchorInvalid)
        }

        guard record.schemaVersion == PersistedAnchor.currentSchemaVersion,
              record.tenantID == principal.tenantID,
              record.userID == principal.userID,
              Self.isValid(bootSessionIdentifier: record.bootSessionID),
              record.signedServerTimeEpochSeconds.isFinite,
              Self.isValid(uptime: record.receiptUptime) else {
            try? persistence.remove(for: principal)
            return .failure(.persistedAnchorInvalid)
        }
        guard record.bootSessionID == currentBootSessionID else {
            try? persistence.remove(for: principal)
            return .failure(.bootSessionChanged)
        }
        guard observedUptime >= record.receiptUptime else {
            try? persistence.remove(for: principal)
            return .failure(
                .monotonicUptimeRegressed(
                    previousUptime: record.receiptUptime,
                    observedUptime: observedUptime
                )
            )
        }

        let signedServerTime = Date(
            timeIntervalSince1970: record.signedServerTimeEpochSeconds
        )
        let trustedTime = signedServerTime.addingTimeInterval(
            observedUptime - record.receiptUptime
        )
        guard trustedTime.timeIntervalSince1970.isFinite else {
            try? persistence.remove(for: principal)
            return .failure(.persistedAnchorInvalid)
        }
        return .success(
            Anchor(
                signedServerTime: signedServerTime,
                receiptUptime: record.receiptUptime,
                latestObservedUptime: observedUptime
            )
        )
    }

    private static func isValid(uptime: TimeInterval) -> Bool {
        uptime.isFinite && uptime >= 0
    }

    private static func isValid(bootSessionIdentifier value: String) -> Bool {
        !value.isEmpty &&
            value == value.trimmingCharacters(in: .whitespacesAndNewlines) &&
            value.utf8.count <= 128 &&
            value.unicodeScalars.allSatisfy { scalar in
                scalar.value >= 0x20 && scalar.value != 0x7f
            }
    }

    private static func currentBootSessionIdentifier() -> String? {
        #if canImport(Darwin)
        var requiredSize: size_t = 0
        guard sysctlbyname(
            "kern.bootsessionuuid",
            nil,
            &requiredSize,
            nil,
            0
        ) == 0,
        requiredSize > 1,
        requiredSize <= 256 else {
            return nil
        }

        var bytes = [CChar](repeating: 0, count: requiredSize)
        let status = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname(
                "kern.bootsessionuuid",
                buffer.baseAddress,
                &requiredSize,
                nil,
                0
            )
        }
        guard status == 0, bytes.last == 0 else { return nil }
        let value = String(cString: bytes)
        return isValid(bootSessionIdentifier: value) ? value : nil
        #else
        return nil
        #endif
    }
}
