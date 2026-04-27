//
//  LoadStore.swift
//  EusoTrip Watch App
//
//  Single source of truth on the wrist for the active load + any
//  upcoming assignments. Updated from:
//    1. WCSession `load.active` pushes from the phone
//    2. tRPC `loads.getTrackedLoads` pulls on `refresh(auth:)`
//    3. Offline-queue replay when the watch reconnects
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class LoadStore: ObservableObject {
    static let shared = LoadStore()

    @Published private(set) var active: WatchLoad?
    @Published private(set) var upcoming: [WatchLoad] = []
    @Published private(set) var lastRefresh: Date?

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("loads.json")
    }()

    // MARK: Persistence

    func restore() {
        // Never fall back to a placeholder load — if the watch has no
        // cached snapshot from a previous session, it should render the
        // "no active load" empty state until the phone pushes one or
        // `refresh(auth:)` pulls one from `loads.getTrackedLoads`.
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            active = snap.active
            upcoming = snap.upcoming
            lastRefresh = snap.ts
        }
    }

    /// Called when the iOS side pushes a "cleared" load event (no active
    /// assignment). Wipes the persisted cache too so the empty state
    /// survives a watch relaunch.
    func clearActive() {
        active = nil
        lastRefresh = Date()
        persist()
        ComplicationRefresher.shared.reloadTimelines()
    }

    private func persist() {
        let snap = Snapshot(active: active, upcoming: upcoming, ts: Date())
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Network

    /// Pull loads.getTrackedLoads for the active driver.
    func refresh(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON("loads.getTrackedLoads")
            if let parsed = try? JSONDecoder().decode(TRPCEnvelope.self, from: data) {
                let loads = parsed.result.data.json.map { $0.asWatchLoad }
                active = loads.first
                upcoming = Array(loads.dropFirst())
                lastRefresh = Date()
                persist()
                if let first = loads.first { seedCRDTIfNeeded(for: first) }
                ComplicationRefresher.shared.reloadTimelines()
            }
        } catch {
            // swallow — keep the stale local copy
        }
    }

    /// Seed a FleetCRDT slot for the given load if we don't already
    /// have one. Idempotent — subsequent calls with the same loadId
    /// are no-ops, preserving any local mutations that have already
    /// happened against this slot.
    private func seedCRDTIfNeeded(for load: WatchLoad) {
        FleetCRDT.shared.seedLoadIfEmpty(
            loadId: load.id,
            lifecycle: load.status,
            assignedDriverId: "",
            estimatedArrivalAt: load.deliverBy,
            podUploaded: false,
            notes: ""
        )
    }

    /// Update the load's lifecycle string and also tick the FleetCRDT
    /// slot so the mutation fans out to peers + the iOS companion on
    /// next reconnect. Callers that only need the UI-side change should
    /// prefer this over writing directly to `active.status` (which
    /// bypasses the CRDT and would lose causality on merge).
    func updateLifecycle(_ newStatus: String) {
        guard let load = active else { return }
        active = WatchLoad(
            id: load.id,
            displayId: load.displayId,
            originCity: load.originCity,
            originState: load.originState,
            destCity: load.destCity,
            destState: load.destState,
            pickupAt: load.pickupAt,
            deliverBy: load.deliverBy,
            ratePerMile: load.ratePerMile,
            totalRate: load.totalRate,
            miles: load.miles,
            status: newStatus,
            hazmat: load.hazmat,
            temperatureF: load.temperatureF,
            equipment: load.equipment,
            brokerName: load.brokerName
        )
        FleetCRDT.shared.mutateLoad(load.id, keyPath: \.lifecycle, to: newStatus)
        persist()
        // Fan the CRDT snapshot back to the iOS companion so the
        // server ledger eventually catches up with the wrist's view.
        if let data = FleetCRDT.shared.exportLoad(load.id) {
            WatchConnectivityManager.shared.forwardLoadCRDT(snapshot: data)
        }
    }

    /// Apply a push from the iOS app (WCSession load.active).
    func applyRemote(json: [String: Any]) {
        let load = WatchLoad(
            id: json["id"] as? String ?? "unknown",
            displayId: json["displayId"] as? String ?? "LD-----",
            originCity: json["originCity"] as? String ?? "",
            originState: json["originState"] as? String ?? "",
            destCity: json["destCity"] as? String ?? "",
            destState: json["destState"] as? String ?? "",
            pickupAt: parseDate(json["pickupAt"]) ?? Date().addingTimeInterval(3600),
            deliverBy: parseDate(json["deliverBy"]) ?? Date().addingTimeInterval(3600 * 6),
            ratePerMile: json["ratePerMile"] as? Double,
            totalRate: json["totalRate"] as? Double,
            miles: json["miles"] as? Double,
            status: json["status"] as? String ?? "assigned",
            hazmat: json["hazmat"] as? Bool ?? false,
            temperatureF: json["temperatureF"] as? Int,
            equipment: json["equipment"] as? String,
            brokerName: json["brokerName"] as? String
        )
        active = load
        lastRefresh = Date()
        persist()
        seedCRDTIfNeeded(for: load)
        ComplicationRefresher.shared.reloadTimelines()
    }

    // MARK: Helpers

    private func parseDate(_ any: Any?) -> Date? {
        if let iso = any as? String,
           let d = ISO8601DateFormatter.iso.date(from: iso) { return d }
        if let unix = any as? Double { return Date(timeIntervalSince1970: unix) }
        return nil
    }

    // MARK: tRPC decoding

    private struct TRPCEnvelope: Decodable {
        struct Result: Decodable {
            struct DataContainer: Decodable {
                let json: [RemoteLoad]
            }
            let data: DataContainer
        }
        let result: Result
    }

    private struct RemoteLoad: Decodable {
        let id: String
        let displayId: String?
        let originCity: String?
        let originState: String?
        let destinationCity: String?
        let destinationState: String?
        let pickupAt: String?
        let deliverBy: String?
        let ratePerMile: Double?
        let totalRate: Double?
        let miles: Double?
        let status: String?
        let hazmat: Bool?
        let temperatureF: Int?
        let equipment: String?
        let brokerName: String?

        var asWatchLoad: WatchLoad {
            WatchLoad(
                id: id,
                displayId: displayId ?? id,
                originCity: originCity ?? "",
                originState: originState ?? "",
                destCity: destinationCity ?? "",
                destState: destinationState ?? "",
                pickupAt: ISO8601DateFormatter.iso.date(from: pickupAt ?? "") ?? Date().addingTimeInterval(3600),
                deliverBy: ISO8601DateFormatter.iso.date(from: deliverBy ?? "") ?? Date().addingTimeInterval(6 * 3600),
                ratePerMile: ratePerMile,
                totalRate: totalRate,
                miles: miles,
                status: status ?? "assigned",
                hazmat: hazmat ?? false,
                temperatureF: temperatureF,
                equipment: equipment,
                brokerName: brokerName
            )
        }
    }

    private struct Snapshot: Codable {
        let active: WatchLoad?
        let upcoming: [WatchLoad]
        let ts: Date
    }

    #if DEBUG
    /// Simulator-only: seed an active load so the Instrument Panel's
    /// load strip and load-detail card render for visual QA. Matches
    /// the LD-24421 mockup (Shreveport → Dallas, hazmat reefer).
    /// Never runs on a physical watch — the real path is either a
    /// WCSession `load.active` push from the iPhone or a tRPC pull via
    /// `refresh(auth:)`.
    func seedMockActiveForSimulator() {
        guard active == nil else { return }
        let cal = Calendar.current
        let pickup = cal.date(bySettingHour: 9, minute: 15, second: 0, of: Date()) ?? Date()
        let deliver = cal.date(bySettingHour: 18, minute: 40, second: 0, of: Date()) ?? Date().addingTimeInterval(9 * 3600)
        active = WatchLoad(
            id: "sim-24421",
            displayId: "LD-24421",
            originCity: "Shreveport",
            originState: "LA",
            destCity: "Dallas",
            destState: "TX",
            pickupAt: pickup,
            deliverBy: deliver,
            ratePerMile: 3.94,
            totalRate: 2440,
            miles: 620,
            status: "assigned",
            hazmat: true,
            temperatureF: 34,
            equipment: "reefer",
            brokerName: "Simulator"
        )
        lastRefresh = Date()
    }
    #endif
}

extension ISO8601DateFormatter {
    /// Shared parser for tRPC ISO timestamps. `nonisolated(unsafe)`
    /// because `ISO8601DateFormatter` is documented thread-safe for
    /// `.date(from:)` reads after configuration, and decoders run on
    /// background actors; without this annotation Swift 6 default-
    /// MainActor isolation flags every off-main read.
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
