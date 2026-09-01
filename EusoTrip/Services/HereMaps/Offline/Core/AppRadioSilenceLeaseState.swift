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
