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
import SwiftUI

@MainActor
final class HOSStore: ObservableObject {
    static let shared = HOSStore()

    @Published private(set) var current: WatchHOS = WatchHOS.placeholder
    @Published private(set) var lastRefresh: Date?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
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
    func applyRemote(status: String, driveRemainingMinutes: Int, windowRemainingMinutes: Int) {
        var snapshot = current
        snapshot.status = HOSStatus(rawValue: status) ?? .off
        snapshot.driveRemainingMinutes = driveRemainingMinutes
        snapshot.windowRemainingMinutes = windowRemainingMinutes
        snapshot.statusSince = Date()
        current = snapshot
        lastRefresh = Date()
        persist()
        ComplicationRefresher.shared.reloadTimelines()
    }

    // MARK: Local status changes

    /// Change duty status from the wrist. Logs the event server-side
    /// and optimistically updates the wrist UI.
    func changeStatus(to newStatus: HOSStatus, auth: AuthStore, connectivity: WatchConnectivityManager) async {
        // Optimistic
        var snapshot = current
        snapshot.status = newStatus
        snapshot.statusSince = Date()
        current = snapshot
        persist()
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
