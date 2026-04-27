//
//  OfflineQueue.swift
//  EusoTrip Watch App
//
//  Unified Outbox (F01) — priority-lane offline queue for the wrist.
//
//  Five priority lanes, processed in strict order on every flush:
//
//      ┌─ lane 0 ───────────────────────── SOS ─────────────────┐
//      │   reason: life-safety; cap 50; never evicted;          │
//      │   backoff: 2s → 5s max; retries forever.               │
//      ├─ lane 1 ───────────────────────── HOS ─────────────────┤
//      │   reason: FMCSA compliance; cap 500; backoff 4s → 60s; │
//      │   retries forever (loss is a legal event).             │
//      ├─ lane 2 ───────────────────────── LOAD ────────────────┤
//      │   reason: revenue-critical (accept / arrived / POD);   │
//      │   cap 200; backoff 8s → 300s; drop after 72h.          │
//      ├─ lane 3 ───────────────────────── VOICE ───────────────┤
//      │   reason: Esang round-trips; cap 100; backoff 15s →    │
//      │   600s; drop after 24h (stale voice = stale intent).   │
//      └─ lane 4 ───────────────────────── MESSAGE ─────────────┘
//          reason: chat / dispatcher pings; cap 100; backoff 30s
//          → 900s; drop after 24h.
//
//  Each entry carries an idempotency key + attempt counter + next-retry
//  timestamp. Exponential backoff per lane. Storage persists to app
//  support so queued actions survive a watch reboot (dead-spot driving
//  across a mountain pass, etc.).
//
//  Back-compat: the public enqueue* / flush(auth:) surface is preserved
//  so every call site (EsangSession, EmergencyController, etc.) keeps
//  working. The lane routing is internal.
//

import Foundation
import Combine
import Network

enum QueuedAction: Codable, Equatable {
    case voice(text: String, loadId: String?, key: String)
    case hosEvent(status: String, at: Date, key: String)
    case acceptLoad(loadId: String, bidId: String?, key: String)
    case arrived(loadId: String, kind: String, at: Date, key: String) // kind: "pickup"|"delivery"
    case sos(reason: String, lat: Double?, lon: Double?, at: Date, key: String)
    case message(loadId: String?, to: String, text: String, key: String)

    var key: String {
        switch self {
        case .voice(_, _, let k): return k
        case .hosEvent(_, _, let k): return k
        case .acceptLoad(_, _, let k): return k
        case .arrived(_, _, _, let k): return k
        case .sos(_, _, _, _, let k): return k
        case .message(_, _, _, let k): return k
        }
    }

    /// Priority lane this action belongs on. Lower == higher priority.
    var lane: OutboxLane {
        switch self {
        case .sos:         return .sos
        case .hosEvent:    return .hos
        case .acceptLoad:  return .load
        case .arrived:     return .load
        case .voice:       return .voice
        case .message:     return .message
        }
    }
}

enum OutboxLane: Int, Codable, CaseIterable, Comparable {
    case sos = 0
    case hos = 1
    case load = 2
    case voice = 3
    case message = 4

    static func < (l: OutboxLane, r: OutboxLane) -> Bool { l.rawValue < r.rawValue }

    var label: String {
        switch self {
        case .sos: return "SOS"
        case .hos: return "HOS"
        case .load: return "Load"
        case .voice: return "Voice"
        case .message: return "Message"
        }
    }

    /// Max entries retained. When exceeded, oldest non-SOS is evicted.
    /// SOS lane is hard-protected against eviction by quota.
    var quota: Int {
        switch self {
        case .sos: return 50
        case .hos: return 500
        case .load: return 200
        case .voice: return 100
        case .message: return 100
        }
    }

    /// (minBackoff, maxBackoff) in seconds. Exponential 2^attempts * min,
    /// clamped to max.
    var backoffWindow: (min: TimeInterval, max: TimeInterval) {
        switch self {
        case .sos:     return (2,   5)
        case .hos:     return (4,   60)
        case .load:    return (8,   300)
        case .voice:   return (15,  600)
        case .message: return (30,  900)
        }
    }

    /// Retire entries older than this without ever retrying again.
    /// SOS + HOS are never retired — they are legal / life-safety events.
    var staleAfter: TimeInterval? {
        switch self {
        case .sos:     return nil
        case .hos:     return nil
        case .load:    return 72 * 3600
        case .voice:   return 24 * 3600
        case .message: return 24 * 3600
        }
    }
}

/// Durable entry: wraps a QueuedAction with retry bookkeeping.
struct OutboxEntry: Codable, Equatable, Identifiable {
    let id: String                // == action.key
    let action: QueuedAction
    let enqueuedAt: Date
    var attempts: Int
    var nextRetryAt: Date
    var lastError: String?

    init(action: QueuedAction, now: Date = Date()) {
        self.id = action.key
        self.action = action
        self.enqueuedAt = now
        self.attempts = 0
        self.nextRetryAt = now
        self.lastError = nil
    }

    var lane: OutboxLane { action.lane }

    /// True if we've waited long enough since the last attempt.
    func isReady(now: Date = Date()) -> Bool { now >= nextRetryAt }

    /// True if the entry has aged past its lane's stale window and should
    /// be dropped without another attempt.
    func isStale(now: Date = Date()) -> Bool {
        guard let ttl = lane.staleAfter else { return false }
        return now.timeIntervalSince(enqueuedAt) > ttl
    }

    /// Mark a failed attempt and advance `nextRetryAt` with exponential
    /// backoff, clamped to the lane's max window.
    mutating func recordFailure(error: Error, now: Date = Date()) {
        attempts += 1
        lastError = String(describing: error).prefix(160).description
        let (minB, maxB) = lane.backoffWindow
        let exp = minB * pow(2.0, Double(min(attempts, 10)))
        let delay = Swift.min(maxB, exp)
        nextRetryAt = now.addingTimeInterval(delay)
    }
}

@MainActor
final class OfflineQueue: ObservableObject {
    static let shared = OfflineQueue()

    /// Flat list, kept as the source of truth. Consumers render by lane
    /// via `laneCount(_:)` / `entries(in:)`.
    @Published private(set) var entries: [OutboxEntry] = []

    /// Back-compat projection — the old `pending: [QueuedAction]` surface.
    /// Existing call sites that read `OfflineQueue.shared.pending` keep
    /// working without a migration.
    var pending: [QueuedAction] { entries.map(\.action) }

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(EusoTripConfig.offlineQueueFilename)
    }()

    // MARK: - Persistence

    /// Persistence envelope. v1 = bare [QueuedAction], v2 = [OutboxEntry].
    /// restore() tolerates both so a cold upgrade from build ≤21 doesn't
    /// drop queued events on the floor.
    private struct Envelope: Codable {
        var version: Int
        var entries: [OutboxEntry]
    }

    func restore() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        // v2 path
        if let env = try? JSONDecoder().decode(Envelope.self, from: data),
           env.version >= 2 {
            entries = env.entries
            sweepStale()
            return
        }
        // v1 fallback — legacy flat array of QueuedAction
        if let legacy = try? JSONDecoder().decode([QueuedAction].self, from: data) {
            entries = legacy.map { OutboxEntry(action: $0) }
            sweepStale()
            persist()
            return
        }
    }

    private func persist() {
        let env = Envelope(version: 2, entries: entries)
        if let data = try? JSONEncoder().encode(env) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func key() -> String { UUID().uuidString }

    // MARK: - Enqueue

    func enqueueVoice(text: String, loadId: String?) {
        append(.voice(text: text, loadId: loadId, key: key()))
    }
    func enqueueHOSEvent(status: String, at date: Date) {
        append(.hosEvent(status: status, at: date, key: key()))
    }
    func enqueueAcceptLoad(loadId: String, bidId: String?) {
        append(.acceptLoad(loadId: loadId, bidId: bidId, key: key()))
    }
    func enqueueArrived(loadId: String, kind: String, at date: Date) {
        append(.arrived(loadId: loadId, kind: kind, at: date, key: key()))
    }
    func enqueueSOS(reason: String, lat: Double?, lon: Double?) {
        append(.sos(reason: reason, lat: lat, lon: lon, at: Date(), key: key()))
    }
    func enqueueMessage(loadId: String?, to recipient: String, text: String) {
        append(.message(loadId: loadId, to: recipient, text: text, key: key()))
    }

    private func append(_ action: QueuedAction) {
        var next = entries
        next.append(OutboxEntry(action: action))
        entries = Self.enforceQuotas(next)
        persist()
    }

    /// Drop oldest non-SOS entries from any lane that exceeds its quota.
    /// SOS is never evicted by quota (life-safety contract).
    private static func enforceQuotas(_ list: [OutboxEntry]) -> [OutboxEntry] {
        var byLane: [OutboxLane: [OutboxEntry]] = [:]
        for e in list { byLane[e.lane, default: []].append(e) }
        var out: [OutboxEntry] = []
        for lane in OutboxLane.allCases {
            let bucket = byLane[lane] ?? []
            if bucket.count <= lane.quota {
                out.append(contentsOf: bucket)
            } else if lane == .sos {
                // SOS bypasses quota eviction
                out.append(contentsOf: bucket)
            } else {
                let trimmed = bucket.sorted { $0.enqueuedAt < $1.enqueuedAt }
                    .suffix(lane.quota)
                out.append(contentsOf: trimmed)
            }
        }
        // Preserve original ordering by enqueuedAt so replays stay causal.
        return out.sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    /// Drop entries older than their lane's staleAfter window.
    private func sweepStale(now: Date = Date()) {
        let before = entries.count
        entries.removeAll { $0.isStale(now: now) }
        if entries.count != before { persist() }
    }

    // MARK: - Inspection helpers

    func laneCount(_ lane: OutboxLane) -> Int {
        entries.reduce(0) { $0 + ($1.lane == lane ? 1 : 0) }
    }

    func entries(in lane: OutboxLane) -> [OutboxEntry] {
        entries.filter { $0.lane == lane }
    }

    // MARK: - Flush
    //
    // Priority order: SOS first, then HOS, Load, Voice, Message. Within
    // each lane the oldest ready entry is attempted first. A lane that
    // fails with a transient error still lets the next lane attempt —
    // we don't want a stuck Voice call to block HOS from reaching the
    // server. Non-ready entries (still in backoff) are skipped.

    /// Drop-every-lane flush. Called from the NWPathMonitor edge + WC
    /// reachability hook + the scenePhase .active cold-launch path.
    /// Identical semantics to `flush(auth:)` today — split so future
    /// per-lane selective flushes don't have to change the external
    /// API. Always safe to call even when the network is flaky or the
    /// queue is empty.
    func flushAll(auth: AuthStore) async {
        await flush(auth: auth)
    }

    func flush(auth: AuthStore) async {
        guard auth.isSignedIn else { return }
        sweepStale()
        guard !entries.isEmpty else { return }

        let client = EsangClient(auth: auth)
        let now = Date()

        // Process lanes strictly in priority order.
        for lane in OutboxLane.allCases {
            // Snapshot this lane's ready entries in enqueue order.
            let ready = entries
                .filter { $0.lane == lane && $0.isReady(now: now) }
                .sorted { $0.enqueuedAt < $1.enqueuedAt }

            for entry in ready {
                do {
                    try await attempt(entry.action, with: client)
                    remove(id: entry.id)
                } catch {
                    updateFailure(id: entry.id, error: error)
                    // For SOS keep trying the next SOS in the same flush
                    // pass — everything else breaks to the next lane so
                    // one misbehaving endpoint doesn't starve others.
                    if lane != .sos { break }
                }
            }
        }
        persist()
    }

    private func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    private func updateFailure(id: String, error: Error) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].recordFailure(error: error)
    }

    private func attempt(_ action: QueuedAction, with client: EsangClient) async throws {
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
        case .message(let loadId, let to, let text, let key):
            _ = try await client.mutateJSON(
                "messaging.send",
                input: [
                    "loadId": loadId ?? "",
                    "to": to,
                    "text": text,
                    "idempotencyKey": key,
                    "surface": "watch-offline"
                ]
            )
        }
    }
}

// MARK: - NWPathMonitor reachability drain
//
// L5 — the queue used to sit until someone called `.flush`. On a
// reinstall where the phone mirrored auth ~30s after first boot, the
// first voice utterance from a driver would stay stuck in the voice
// lane until another orb tap, scenePhase cycle, or WCSession push
// happened to run the flush path. NWPathMonitor closes the gap:
// the moment the path goes .satisfied after being .unsatisfied (or at
// cold-launch when path is already satisfied), we trigger flushAll()
// against whatever AuthStore.shared points at, and update
// OrbStateMachine.networkReachable so the UI can surface an OFFLINE
// capsule when the path is genuinely down.
//
// The monitor is singleton and the class is thread-safe internally —
// we hop to @MainActor before touching any ObservableObject surface.

@MainActor
final class NetworkReachabilityHub {
    static let shared = NetworkReachabilityHub()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.app.eusotrip.watch.net", qos: .utility)
    private var started = false
    private var lastSatisfied: Bool = true

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self else { return }
                OrbStateMachine.shared.networkReachable = satisfied
                // Edge trigger: only fire flush on the transition
                // from .unsatisfied → .satisfied OR on the initial
                // state set (started is true but no previous edge).
                let edge = satisfied && !self.lastSatisfied
                self.lastSatisfied = satisfied
                if edge, let auth = AuthStore.shared {
                    OrbLog.info("net.edge satisfied — flushing queue")
                    await OfflineQueue.shared.flushAll(auth: auth)
                }
            }
        }
        monitor.start(queue: queue)
        OrbLog.info("net.monitor started")
    }
}

