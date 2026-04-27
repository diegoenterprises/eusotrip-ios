//
//  HOSStore.swift
//  EusoTrip Watch App
//
//  Hours-of-service source of truth on the wrist.
//  - Updated from iOS via WCSession (`hos.update`)
//  - Polled from tRPC `eld.getSummary` on refresh
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
    /// `eld.getSummary`. The previous behavior (initialize to a mid-
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
            let data = try await client.queryJSON("eld.getSummary")
            if let env = try? JSONDecoder().decode(Envelope.self, from: data) {
                current = env.result.data.json.asHOS
                lastRefresh = Date()
                persist()
                ComplicationRefresher.shared.reloadTimelines()
            }
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

        // Best-effort direct call (in case phone is unreachable)
        if auth.isSignedIn {
            do {
                let client = EsangClient(auth: auth)
                _ = try await client.mutateJSON(
                    "hos.changeStatus",
                    input: [
                        "status": newStatus.rawValue,
                        "source": "watch",
                        "ts": Date().timeIntervalSince1970
                    ]
                )
            } catch {
                // Queue for retry
                OfflineQueue.shared.enqueueHOSEvent(status: newStatus.rawValue, at: Date())
            }
        }
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

    private struct Remote: Decodable {
        let status: String?
        let driveRemainingMinutes: Int?
        let windowRemainingMinutes: Int?
        let cycleRemainingMinutes: Int?
        var asHOS: WatchHOS {
            WatchHOS(
                status: HOSStatus(rawValue: status ?? "off") ?? .off,
                driveRemainingMinutes: driveRemainingMinutes ?? 0,
                windowRemainingMinutes: windowRemainingMinutes ?? 0,
                cycleRemainingMinutes: cycleRemainingMinutes ?? 0,
                statusSince: Date()
            )
        }
    }

    private struct Snapshot: Codable {
        let hos: WatchHOS
        let ts: Date
    }
}
