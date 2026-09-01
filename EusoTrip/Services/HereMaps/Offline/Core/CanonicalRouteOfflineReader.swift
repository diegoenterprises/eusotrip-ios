//
//  CanonicalRouteOfflineReader.swift
//  EusoTrip
//
//  Account- and subject-scoped read boundary for persisted Rail/Vessel route
//  packages. Only a fresh package verified by the app-owned composition is
//  returned to an offline surface.
//

import Foundation

enum CanonicalRouteOfflineReadError: Error, Equatable, LocalizedError {
    case missing
    case stale
    case verifiedPackageMismatch

    var errorDescription: String? {
        switch self {
        case .missing:
            return "No verified offline route has been saved for this freight record."
        case .stale:
            return "The saved route is no longer fresh enough for operational use. Reconnect to verify it again."
        case .verifiedPackageMismatch:
            return "The saved route does not match this account and freight record."
        }
    }
}

@MainActor
struct CanonicalRouteOfflineReader {
    /// Route plans are operational data, not static cartography. Even when a
    /// plan has a later signed validUntil value, EusoTrip requires a server
    /// observation no older than 24 hours before presenting it as usable.
    static let maximumServerObservationAge: TimeInterval = 24 * 60 * 60

    let composition: OfflineMapProductionComposition

    init(composition: OfflineMapProductionComposition) {
        self.composition = composition
    }

    func freshPackage(
        subject: CanonicalRouteFreightSubject,
        authenticatedUser: AuthUser
    ) async throws -> CanonicalRoutePackage {
        try subject.validate()
        let principal = try CanonicalRouteAuthenticatedPrincipal(
            authenticatedUser: authenticatedUser
        )
        let scope = try principal.scope(for: subject)
        let policy = try CanonicalRouteFreshnessPolicy(
            maximumServerObservationAge: Self.maximumServerObservationAge
        )
        let observation = try await composition.observeCanonicalRoute(
            scope: scope,
            freshnessPolicy: policy
        )

        switch observation.status {
        case .missing:
            throw CanonicalRouteOfflineReadError.missing
        case .stale:
            throw CanonicalRouteOfflineReadError.stale
        case .fresh:
            guard let package = observation.package,
                  package.scope == scope,
                  package.mode == subject.expectedRouteMode else {
                throw CanonicalRouteOfflineReadError.verifiedPackageMismatch
            }
            return package
        }
    }
}
