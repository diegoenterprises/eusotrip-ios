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
import SwiftUI

@MainActor
final class LoadStore: ObservableObject {
    static let shared = LoadStore()

    @Published private(set) var active: WatchLoad?
    @Published private(set) var upcoming: [WatchLoad] = []
    @Published private(set) var lastRefresh: Date?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("loads.json")
    }()

    // MARK: Persistence

    func restore() {
        if let data = try? Data(contentsOf: fileURL),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            active = snap.active
            upcoming = snap.upcoming
            lastRefresh = snap.ts
        } else {
            active = WatchLoad.placeholder
        }
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
                ComplicationRefresher.shared.reloadTimelines()
            }
        } catch {
            // swallow — keep the stale local copy
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
}

extension ISO8601DateFormatter {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
