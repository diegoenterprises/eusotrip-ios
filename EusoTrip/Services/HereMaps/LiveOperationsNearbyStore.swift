//
//  LiveOperationsNearbyStore.swift
//  EusoTrip
//
//  Polls the server-owned Live Operations authority for exact, tenant-
//  authorized observations. It never calls a telemetry provider directly,
//  claims area coverage, authors route geometry, or projects progress.
//

import Foundation
import SwiftUI

@MainActor
final class LiveOperationsNearbyStore: ObservableObject {
    @Published private(set) var result: LiveOperationsClient.NearbyResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false

    let mode: LiveOperationsClient.Mode

    init(mode: LiveOperationsClient.Mode) {
        self.mode = mode
    }

    var operationalObservations: [LiveOperationsClient.Observation] {
        result?.operationalObservations ?? []
    }

    var markers: [HereMarker] {
        operationalObservations.compactMap { observation in
            guard let coordinate = observation.position.coordinate else { return nil }
            let distance = observation.distanceMeters.map {
                String(format: "%.1f mi away", $0 / 1_609.344)
            }
            let label = observation.asset.identityKey
            let evidence = [
                mode.accessibilityName,
                label,
                distance,
                observation.accessibleEvidenceLabel,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")

            return HereMarker(
                at: coordinate,
                kind: mode.markerKind,
                label: label,
                id: "live-operation:\(observation.publicId)",
                observationState: observation.markerState,
                sourceLabel: observation.provider.id,
                accessibilityLabel: evidence
            )
        }
    }

    var status: HereLiveOperationsStatus {
        if let result {
            let observations = result.operationalObservations
            guard !observations.isEmpty else {
                return .init(
                    availability: .empty,
                    freshnessLabel: "Server as of \(result.asOf)",
                    detail: [result.coverage.statement, result.modeLimitation]
                        .joined(separator: " "),
                    observationCount: 0
                )
            }

            let availability: HereLiveOperationsStatus.Availability
            if observations.contains(where: { $0.markerState == .current }) {
                availability = .live
            } else if observations.contains(where: { $0.markerState == .degraded }) {
                availability = .degraded
            } else if observations.contains(where: { $0.markerState == .stale }) {
                availability = .stale
            } else {
                availability = .unavailable
            }

            let providers = Array(Set(observations.map(\.provider.id))).sorted()
            return .init(
                availability: availability,
                sourceLabel: providers.joined(separator: ", "),
                freshnessLabel: "Server as of \(result.asOf)",
                detail: [result.coverage.statement, result.modeLimitation]
                    .joined(separator: " "),
                observationCount: observations.count
            )
        }

        if let errorMessage {
            return .init(
                availability: .unavailable,
                detail: errorMessage,
                observationCount: 0
            )
        }

        return .init(
            availability: .degraded,
            detail: "Checking for authorized \(mode.accessibilityName.lowercased()) observations.",
            observationCount: 0
        )
    }

    func refresh(
        around center: HereLatLng,
        radiusMeters: Int,
        limit: Int = 100
    ) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let response = try await LiveOperationsClient.shared.nearby(
                mode: mode,
                center: center,
                radiusMeters: radiusMeters,
                limit: limit
            )
            guard response.mode == mode else {
                result = nil
                errorMessage = "Live observations do not match this transport mode and were not shown."
                return
            }
            result = response
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            result = nil
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Authorized Live Operations observations are temporarily unavailable."
        }
    }

    /// Designed for a SwiftUI `.task(id:)`; cancellation stops polling when
    /// the screen or center changes. Thirty seconds is intentionally bounded
    /// so the app does not turn an authorized feed into an abusive poller.
    func poll(
        around center: HereLatLng,
        radiusMeters: Int,
        limit: Int = 100,
        intervalSeconds: UInt64 = 30
    ) async {
        repeat {
            await refresh(
                around: center,
                radiusMeters: radiusMeters,
                limit: limit
            )
            guard !Task.isCancelled else { return }
            do {
                try await Task.sleep(
                    nanoseconds: max(15, intervalSeconds) * 1_000_000_000
                )
            } catch {
                return
            }
        } while !Task.isCancelled
    }
}

private extension LiveOperationsClient.Mode {
    var markerKind: HereMarker.Kind {
        switch self {
        case .truck: return .truck
        case .rail: return .rail
        case .vessel: return .vessel
        }
    }

    var accessibilityName: String {
        switch self {
        case .truck: return "Truck"
        case .rail: return "Rail equipment"
        case .vessel: return "Vessel"
        }
    }
}
