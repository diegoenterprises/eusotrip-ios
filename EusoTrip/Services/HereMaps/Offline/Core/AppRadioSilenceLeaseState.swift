//
//  AppRadioSilenceLeaseState.swift
//  EusoTrip
//
//  Pure, source-testable ownership state for the app-wide radio-silence
//  policy. The state deliberately contains no networking or UI dependencies.
//

import Foundation

enum AppRadioSilenceTransportError: Error, LocalizedError, Equatable, Sendable {
    case enforced

    var errorDescription: String? {
        "Network access is paused while the offline journey is active."
    }
}

/// An opaque ownership token. Every successful acquisition must retain its
/// token and release that same token when the protected offline experience
/// ends. Releasing an unknown/already-released token is an idempotent no-op.
struct AppRadioSilenceLease: Hashable, Sendable {
    fileprivate let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

struct AppRadioSilenceLeaseState: Equatable, Sendable {
    enum AcquireTransition: Equatable, Sendable {
        case firstLease
        case nestedLease
    }

    enum ReleaseTransition: Equatable, Sendable {
        case unknownLease
        case stillEnforced
        case finalLeaseReleased
    }

    private var leases: Set<AppRadioSilenceLease> = []

    var isEnforced: Bool { !leases.isEmpty }
    var activeLeaseCount: Int { leases.count }

    mutating func acquire() -> (lease: AppRadioSilenceLease, transition: AcquireTransition) {
        let wasEnforced = isEnforced
        let lease = AppRadioSilenceLease()
        leases.insert(lease)
        return (lease, wasEnforced ? .nestedLease : .firstLease)
    }

    mutating func release(_ lease: AppRadioSilenceLease) -> ReleaseTransition {
        guard leases.remove(lease) != nil else { return .unknownLease }
        return leases.isEmpty ? .finalLeaseReleased : .stillEnforced
    }
}

struct AppRadioSilencePhoneMirrorState: Equatable, Sendable {
    private(set) var isEnforced: Bool
    private(set) var revision: Int
    private(set) var epoch: String

    init(isEnforced: Bool, revision: Int, epoch: String) {
        self.isEnforced = isEnforced
        self.revision = max(0, revision)
        self.epoch = epoch
    }

    mutating func setEnforced(
        _ enforced: Bool,
        makeEpoch: () -> String = { UUID().uuidString }
    ) {
        guard enforced != isEnforced else { return }
        advance(enforced: enforced, makeEpoch: makeEpoch)
    }

    fileprivate mutating func markProcessRestarted(
        enforced: Bool,
        makeEpoch: () -> String
    ) {
        // Every restart publishes a strictly newer explicit edge even when the
        // bit is unchanged. The atomic app-group marker decides the bit: a
        // background/extension wake after a crash must retain ENFORCED, while
        // only a successful true-foreground RELEASE may publish false.
        advance(enforced: enforced, makeEpoch: makeEpoch)
    }

    private mutating func advance(
        enforced: Bool,
        makeEpoch: () -> String
    ) {
        if revision == Int.max {
            epoch = Self.validEpoch(makeEpoch())
            revision = 0
        } else {
            revision += 1
        }
        isEnforced = enforced
    }

    fileprivate static func validEpoch(_ candidate: String) -> String {
        candidate.isEmpty ? UUID().uuidString : candidate
    }
}

struct AppRadioSilencePhoneMirrorLegacyState: Equatable, Sendable {
    let isEnforced: Bool?
    let revision: Int?
    let epoch: String?

    static let empty = Self(isEnforced: nil, revision: nil, epoch: nil)

    var hasAnyValue: Bool {
        isEnforced != nil || revision != nil || epoch != nil
    }
}

private struct AppRadioSilencePhoneMirrorPersistedSnapshot: Codable {
    let version: Int
    let isEnforced: Bool
    let revision: Int
    let epoch: String
}

enum AppRadioSilencePhoneMirrorPersistence {
    static let currentVersion = 1

    static func encode(_ state: AppRadioSilencePhoneMirrorState) throws -> Data {
        guard state.revision >= 0, !state.epoch.isEmpty else {
            throw CocoaError(.coderInvalidValue)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            AppRadioSilencePhoneMirrorPersistedSnapshot(
                version: currentVersion,
                isEnforced: state.isEnforced,
                revision: state.revision,
                epoch: state.epoch
            )
        )
    }

    /// Restores one atomic envelope (or one complete legacy tuple), then mints
    /// a strictly newer process-restart edge before WCSession can publish.
    /// `sharedStateIsEnforced` comes from the atomic app-group marker; it is not
    /// inferred from process-local leases, which do not survive a crash.
    /// A corrupt new envelope starts a new epoch instead of trusting partial
    /// legacy keys that may represent different writes.
    static func restoreForProcessRestart(
        snapshotData: Data?,
        legacy: AppRadioSilencePhoneMirrorLegacyState = .empty,
        sharedStateIsEnforced: Bool,
        makeEpoch: () -> String = { UUID().uuidString }
    ) -> AppRadioSilencePhoneMirrorState {
        let restored: AppRadioSilencePhoneMirrorState?
        if let snapshotData {
            if let snapshot = try? JSONDecoder().decode(
                AppRadioSilencePhoneMirrorPersistedSnapshot.self,
                from: snapshotData
            ),
            snapshot.version == currentVersion,
            snapshot.revision >= 0,
            !snapshot.epoch.isEmpty {
                restored = .init(
                    isEnforced: snapshot.isEnforced,
                    revision: snapshot.revision,
                    epoch: snapshot.epoch
                )
            } else {
                restored = nil
            }
        } else if legacy.hasAnyValue,
                  let isEnforced = legacy.isEnforced,
                  let revision = legacy.revision,
                  revision >= 0,
                  let epoch = legacy.epoch,
                  !epoch.isEmpty {
            restored = .init(
                isEnforced: isEnforced,
                revision: revision,
                epoch: epoch
            )
        } else {
            restored = nil
        }

        guard var state = restored else {
            return .init(
                isEnforced: sharedStateIsEnforced,
                revision: 0,
                epoch: AppRadioSilencePhoneMirrorState.validEpoch(makeEpoch())
            )
        }
        state.markProcessRestarted(
            enforced: sharedStateIsEnforced,
            makeEpoch: makeEpoch
        )
        return state
    }
}
