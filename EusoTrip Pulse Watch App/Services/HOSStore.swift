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
            lastRefresh = snap.ts
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
                current = snapshot
                lastRefresh = Date()
                persist()
                ComplicationRefresher.shared.reloadTimelines()
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
    func applyRemote(status: String, driveRemainingMinutes: Int, windowRemainingMinutes: Int, cycleRemainingMinutes: Int = 0) {
        let previousStatus = current.status.rawValue
        var snapshot = current
        snapshot.status = HOSStatus(rawValue: status) ?? .off
        snapshot.driveRemainingMinutes = driveRemainingMinutes
        snapshot.windowRemainingMinutes = windowRemainingMinutes
        if cycleRemainingMinutes > 0 {
            snapshot.cycleRemainingMinutes = cycleRemainingMinutes
        }
        snapshot.statusSince = Date()
        current = snapshot
        lastRefresh = Date()
        persist()
        // Chain the status transition into the tamper-evident audit log
        // + CRDT, so a wrist-originated or phone-originated change both
        // produce the same FMCSA-defensible artifact. Gated by their own
        // config flags so production can enable them independently.
        chainHOSStatusChange(
            from: previousStatus,
            to: snapshot.status.rawValue,
            source: "remote"
        )
        ComplicationRefresher.shared.reloadTimelines()
    }

    // MARK: Local status changes

    /// Change duty status from the wrist. Logs the event server-side
    /// and optimistically updates the wrist UI.
    func changeStatus(to newStatus: HOSStatus, auth: AuthStore, connectivity: WatchConnectivityManager) async {
        let previousStatus = current.status.rawValue
        // Optimistic
        var snapshot = current
        snapshot.status = newStatus
        snapshot.statusSince = Date()
        current = snapshot
        persist()
        // F12 + Q4 — chain the transition into the CRDT + audit log so
        // offline-initiated status changes are defensibly timestamped
        // and deterministically mergeable when we come back online.
        chainHOSStatusChange(
            from: previousStatus,
            to: newStatus.rawValue,
            source: "watch"
        )
        ComplicationRefresher.shared.reloadTimelines()

        // Report via the phone (keeps FMCSA log on a single actor)
        connectivity.reportHOSStatusChange(
            status: newStatus.rawValue,
            odometer: nil,
            location: nil
        )

        // Best-effort direct call (in case phone is unreachable).
        // Server contract (routers/hos.ts:200-205) REQUIRES
        // { newStatus: dutyStatusSchema, location: string } — the old
        // { status, source, ts } shape was a zod BAD_REQUEST on every
        // call, so no wrist duty change ever landed.
        if auth.isSignedIn {
            do {
                let client = EsangClient(auth: auth)
                _ = try await client.mutateJSON(
                    "hos.changeStatus",
                    input: [
                        "newStatus": Self.serverDutyStatus(newStatus.rawValue),
                        "location": "watch",
                        "idempotencyKey": UUID().uuidString
                    ]
                )
            } catch {
                // Queue for retry
                OfflineQueue.shared.enqueueHOSEvent(status: newStatus.rawValue, at: Date())
            }
        }
    }

    /// Watch enum rawValue → server dutyStatusSchema value. Only "off"
    /// differs ("off" vs "off_duty"); the rest pass through.
    static func serverDutyStatus(_ watchRaw: String) -> String {
        watchRaw == "off" ? "off_duty" : watchRaw
    }

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
        let status: String?
        let drivingRemaining: Double?
        let onDutyRemaining: Double?
        let cycleRemaining: Double?

        /// nil when the payload carried no real values — the caller
        /// must keep the existing snapshot in that case.
        var asHOS: WatchHOS? {
            guard status != nil
                || drivingRemaining != nil
                || onDutyRemaining != nil
                || cycleRemaining != nil else { return nil }
            let mapped: HOSStatus = {
                switch (status ?? "").lowercased() {
                case "off_duty", "off": return .off
                case "sleeper":         return .sleeper
                case "driving":         return .driving
                case "on_duty":         return .onDuty
                default:                return .off
                }
            }()
            func minutes(_ hours: Double?) -> Int {
                guard let hours else { return 0 }
                return max(0, Int((hours * 60).rounded()))
            }
            return WatchHOS(
                status: mapped,
                driveRemainingMinutes: minutes(drivingRemaining),
                windowRemainingMinutes: minutes(onDutyRemaining),
                cycleRemainingMinutes: minutes(cycleRemaining),
                statusSince: Date()
            )
        }
    }

    private struct Snapshot: Codable {
        let hos: WatchHOS
        let ts: Date
    }
}
