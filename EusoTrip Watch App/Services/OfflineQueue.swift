//
//  OfflineQueue.swift
//  EusoTrip Watch App
//
//  Offline-first action queue. Any voice submission, HOS event, bid
//  accept, or SOS ping that can't reach the server at call time goes
//  here with an idempotency key and retries on the next `flush(auth:)`.
//
//  Persisted to Application Support so queued actions survive a watch
//  reboot (dead-spot driving across a mountain pass, etc.).
//

import Foundation

enum QueuedAction: Codable, Equatable {
    case voice(text: String, loadId: String?, key: String)
    case hosEvent(status: String, at: Date, key: String)
    case acceptLoad(loadId: String, bidId: String?, key: String)
    case arrived(loadId: String, kind: String, at: Date, key: String) // kind: "pickup"|"delivery"
    case sos(reason: String, lat: Double?, lon: Double?, at: Date, key: String)

    var key: String {
        switch self {
        case .voice(_, _, let k): return k
        case .hosEvent(_, _, let k): return k
        case .acceptLoad(_, _, let k): return k
        case .arrived(_, _, _, let k): return k
        case .sos(_, _, _, _, let k): return k
        }
    }
}

@MainActor
final class OfflineQueue: ObservableObject {
    static let shared = OfflineQueue()

    @Published private(set) var pending: [QueuedAction] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(EusoTripConfig.offlineQueueFilename)
    }()

    func restore() {
        if let data = try? Data(contentsOf: fileURL),
           let q = try? JSONDecoder().decode([QueuedAction].self, from: data) {
            pending = q
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pending) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func key() -> String { UUID().uuidString }

    // MARK: - Enqueue

    func enqueueVoice(text: String, loadId: String?) {
        pending.append(.voice(text: text, loadId: loadId, key: key()))
        persist()
    }
    func enqueueHOSEvent(status: String, at date: Date) {
        pending.append(.hosEvent(status: status, at: date, key: key()))
        persist()
    }
    func enqueueAcceptLoad(loadId: String, bidId: String?) {
        pending.append(.acceptLoad(loadId: loadId, bidId: bidId, key: key()))
        persist()
    }
    func enqueueArrived(loadId: String, kind: String, at date: Date) {
        pending.append(.arrived(loadId: loadId, kind: kind, at: date, key: key()))
        persist()
    }
    func enqueueSOS(reason: String, lat: Double?, lon: Double?) {
        pending.append(.sos(reason: reason, lat: lat, lon: lon, at: Date(), key: key()))
        persist()
    }

    // MARK: - Flush

    /// Attempt to submit every pending action. Each success is dropped.
    /// Each failure stays queued for the next attempt.
    func flush(auth: AuthStore) async {
        guard auth.isSignedIn, !pending.isEmpty else { return }
        let client = EsangClient(auth: auth)
        var remaining: [QueuedAction] = []
        for action in pending {
            let ok = await attempt(action, with: client)
            if !ok { remaining.append(action) }
        }
        pending = remaining
        persist()
    }

    private func attempt(_ action: QueuedAction, with client: EsangClient) async -> Bool {
        do {
            switch action {
            case .voice(let text, let loadId, let key):
                _ = try await client.mutateJSON(
                    "voiceESANG.processVoiceCommand",
                    input: ["text": text, "loadId": loadId ?? "", "idempotencyKey": key, "surface": "watch-offline"]
                )
            case .hosEvent(let status, let at, let key):
                _ = try await client.mutateJSON(
                    "hos.changeStatus",
                    input: ["status": status, "ts": at.timeIntervalSince1970, "idempotencyKey": key, "source": "watch-offline"]
                )
            case .acceptLoad(let loadId, let bidId, let key):
                _ = try await client.mutateJSON(
                    "loads.accept",
                    input: ["loadId": loadId, "bidId": bidId ?? "", "idempotencyKey": key, "source": "watch-offline"]
                )
            case .arrived(let loadId, let kind, let at, let key):
                _ = try await client.mutateJSON(
                    "loads.logArrival",
                    input: ["loadId": loadId, "kind": kind, "ts": at.timeIntervalSince1970, "idempotencyKey": key]
                )
            case .sos(let reason, let lat, let lon, let at, let key):
                _ = try await client.mutateJSON(
                    "emergencyProtocols.activate",
                    input: [
                        "reason": reason,
                        "lat": lat ?? 0,
                        "lon": lon ?? 0,
                        "ts": at.timeIntervalSince1970,
                        "idempotencyKey": key,
                        "source": "watch-offline"
                    ]
                )
            }
            return true
        } catch {
            return false
        }
    }
}
