//
//  HOSStore.swift
//  EusoTrip Watch App
//
//  Hours-of-service source of truth on the wrist.
//  - Updated from iOS via WCSession (`hos.update`)
//  - Polled from tRPC `hos.getStatus` on refresh (the real per-driver duty proc)
//  - Local driver-initiated status changes (`goOnDuty`, `goOffDuty`,
//    `startDriving`, `sleeperBerth`) hit `hos.changeStatus` (the
//    canonical §395.8 transition endpoint; replaces the deprecated
//    `hos.logEvent`) and get mirrored back immediately so the wrist
//    UI responds in <300ms.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class HOSStore: ObservableObject {
    static let shared = HOSStore()

    /// Empty fixture — status=off, all counters zero. The wrist never
    /// renders synthetic numbers: it shows the empty state until iOS
    /// pushes a `hos.update` or `refresh(auth:)` returns from
    /// `hos.getStatus`. The previous behavior (initialize to a mid-
    /// shift placeholder) leaked fake "4h 12m drive remaining" onto a
    /// just-installed watch.
    @Published private(set) var current: WatchHOS = WatchHOS.empty
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastMutationError: String?

    var currentObservation: WatchHOS? {
        current.hasCurrentObservation() ? current : nil
    }

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hos.json")
    }()

    // MARK: Persistence

    func restore() {
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            current = snap.hos
            lastRefresh = snap.hos.observedAt
        }
    }

    private func persist() {
        let snap = Snapshot(hos: current, ts: Date())
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Network

    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            // `hos.getStatus` (routers/hos.ts:151) is the real per-driver
            // duty proc — the same one the phone's HOSClockService reads.
            // The previous endpoint here (`eld.getSummary`) is a FLEET
            // DEVICE stats proc with zero overlapping keys: its all-nil
            // decode "succeeded" and zeroed the live rings on every
            // foreground, clobbering the phone-pushed snapshot.
            let data = try await client.queryJSON("hos.getStatus")
            if let env = try? JSONDecoder().decode(Envelope.self, from: data),
               let snapshot = env.result.data.json.asHOS {
                // Only apply a remote read that carries REAL values —
                // an unexpected shape can never overwrite a phone-pushed
                // snapshot with fabricated off-duty/zeros.
                applyObservation(snapshot, source: "server")
            }
        } catch EsangError.unauthorized {
            // Expired 7-day wrist JWT looks like a dead connection —
            // kick the phone for a fresh mirror instead of silently
            // serving stale rings forever.
            WatchConnectivityManager.shared.requestAuthMirror()
        } catch {
            // Keep local snapshot
        }
    }

    /// Apply a push from the iOS app via WCSession.
    func applyRemote(
        status: String,
        driveRemainingMinutes: Int,
        windowRemainingMinutes: Int,
        cycleRemainingMinutes: Int,
        tracked: Bool,
        source: String,
        freshness: String
    ) {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tracked,
              let duty = HOSStatus(rawValue: status),
              driveRemainingMinutes >= 0,
              windowRemainingMinutes >= 0,
              cycleRemainingMinutes >= 0,
              !normalizedSource.isEmpty,
              let observedAt = Self.currentObservationDate(freshness) else { return }
        let snapshot = WatchHOS(
            status: duty,
            driveRemainingMinutes: driveRemainingMinutes,
            windowRemainingMinutes: windowRemainingMinutes,
            cycleRemainingMinutes: cycleRemainingMinutes,
            statusSince: observedAt,
            tracked: true,
            source: normalizedSource,
            observedAt: observedAt
        )
        applyObservation(snapshot, source: "phone")
    }

    // MARK: Local status changes

    /// Change duty status from the wrist. The legal state is never updated
    /// optimistically: a real coordinate is required, the server mutation is
    /// idempotent, and the display changes only after a sourced HOS refresh.
    func changeStatus(to newStatus: HOSStatus, auth: AuthStore, connectivity _: WatchConnectivityManager) async {
        lastMutationError = nil
        guard auth.isSignedIn else {
            lastMutationError = "Sign in before changing duty status."
            return
        }
        guard let location = DrivingSessionManager.shared.currentHOSLocationEvidence else {
            lastMutationError = "Current GPS evidence is required before changing duty status."
            return
        }

        let idempotencyKey = UUID().uuidString
        do {
            let client = EsangClient(auth: auth)
            _ = try await client.mutateJSON(
                "hos.changeStatus",
                input: [
                    "newStatus": Self.serverDutyStatus(newStatus.rawValue),
                    "location": location,
                    "idempotencyKey": idempotencyKey
                ]
            )
            await refresh(auth: auth)
        } catch {
            OfflineQueue.shared.enqueueHOSEvent(
                status: newStatus.rawValue,
                location: location,
                at: Date(),
                idempotencyKey: idempotencyKey
            )
            lastMutationError = "Duty change queued with its GPS evidence; the displayed status remains unchanged until confirmed."
        }
    }

    /// Watch enum rawValue → server dutyStatusSchema value. Only "off"
    /// differs ("off" vs "off_duty"); the rest pass through.
    static func serverDutyStatus(_ watchRaw: String) -> String {
        watchRaw == "off" ? "off_duty" : watchRaw
    }

    private func applyObservation(_ snapshot: WatchHOS, source: String) {
        let previousStatus = currentObservation?.status.rawValue
        current = snapshot
        lastRefresh = snapshot.observedAt
        persist()
        if let previousStatus {
            chainHOSStatusChange(
                from: previousStatus,
                to: snapshot.status.rawValue,
                source: source
            )
        }
        ComplicationRefresher.shared.reloadTimelines()
    }

    private static func currentObservationDate(_ raw: String, now: Date = Date()) -> Date? {
        guard let observedAt = fractional.date(from: raw) ?? internet.date(from: raw) else { return nil }
        let age = now.timeIntervalSince(observedAt)
        guard age >= -(5 * 60), age <= 15 * 60 else { return nil }
        return observedAt
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Tamper-evident + CRDT fan-out

    /// Fan a duty-status transition out to BlockchainAudit (Q4 hash chain)
    /// and FleetCRDT (Q3 LWW vector-clock store). Both are no-ops unless
    /// their respective feature flags are on, so this is safe to call
    /// unconditionally from every mutation site. No-ops if the old and
    /// new status are identical (applyRemote can be invoked for a counter
    /// refresh without a state change).
    fileprivate func chainHOSStatusChange(from previous: String, to next: String, source: String) {
        guard previous != next else { return }

        if EusoTripConfig.blockchainAuditEnabled {
            BlockchainAudit.shared.append(
                kind: .hosStatus,
                payload: [
                    "from": previous,
                    "to": next,
                    "source": source,
                    "driveRemaining": String(current.driveRemainingMinutes),
                    "windowRemaining": String(current.windowRemainingMinutes),
                    "cycleRemaining": String(current.cycleRemainingMinutes)
                ]
            )
        }

        if EusoTripConfig.fleetCRDTEnabled {
            FleetCRDT.shared.mutate(\.status, to: next)
            FleetCRDT.shared.mutate(\.driveMinutes, to: current.driveRemainingMinutes)
            FleetCRDT.shared.mutate(\.windowMinutes, to: current.windowRemainingMinutes)
            FleetCRDT.shared.mutate(\.cycleMinutes, to: current.cycleRemainingMinutes)
            FleetCRDT.shared.mutate(\.statusSince, to: current.statusSince)
        }
    }

    // MARK: tRPC decoding

    private struct Envelope: Decodable {
        struct Result: Decodable {
            struct DataContainer: Decodable {
                let json: Remote
            }
            let data: DataContainer
        }
        let result: Result
    }

    /// Mirror of the REAL `hos.getStatus` return (routers/hos.ts:151-164):
    ///   { drivingRemaining: Double (hours), onDutyRemaining: Double,
    ///     cycleRemaining: Double, status: "off_duty"|"sleeper"|
    ///     "driving"|"on_duty", breakRequired, canDrive, ... }
    /// Hours → minutes conversion happens here; the server enum
    /// "off_duty" maps onto the watch enum's "off".
    private struct Remote: Decodable {
        let trackingState: String?
        let tracked: Bool?
        let source: String?
        let freshness: String?
        let status: String?
        let drivingRemaining: Double?
        let onDutyRemaining: Double?
        let cycleRemaining: Double?

        /// Only a complete, current, sourced observation may replace the
        /// watch snapshot. Partial decoder success is not legal HOS evidence.
        var asHOS: WatchHOS? {
            let mapped: HOSStatus?
            switch status?.lowercased() {
            case "off_duty", "off": mapped = .off
            case "sleeper": mapped = .sleeper
            case "driving": mapped = .driving
            case "on_duty": mapped = .onDuty
            default: mapped = nil
            }
            let normalizedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard tracked == true,
                  trackingState == "tracked",
                  let mapped,
                  let normalizedSource, !normalizedSource.isEmpty,
                  let freshness,
                  let observedAt = HOSStore.currentObservationDate(freshness),
                  let drivingRemaining, drivingRemaining.isFinite, drivingRemaining >= 0,
                  let onDutyRemaining, onDutyRemaining.isFinite, onDutyRemaining >= 0,
                  let cycleRemaining, cycleRemaining.isFinite, cycleRemaining >= 0 else {
                return nil
            }
            return WatchHOS(
                status: mapped,
                driveRemainingMinutes: Int((drivingRemaining * 60).rounded()),
                windowRemainingMinutes: Int((onDutyRemaining * 60).rounded()),
                cycleRemainingMinutes: Int((cycleRemaining * 60).rounded()),
                statusSince: observedAt,
                tracked: true,
                source: normalizedSource,
                observedAt: observedAt
            )
        }
    }

    private struct Snapshot: Codable {
        let hos: WatchHOS
        let ts: Date
    }
}
