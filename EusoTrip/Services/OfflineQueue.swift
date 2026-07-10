//
//  OfflineQueue.swift
//  EusoTrip — phone-side Unified Outbox (offline action queue).
//
//  The wrist app already ships this pattern
//  (`EusoTrip Pulse Watch App/Services/OfflineQueue.swift`): a durable,
//  FileManager-backed queue that persists driver mutations when the
//  network is unreachable and replays them — in order, idempotently —
//  the moment connectivity returns. This is the phone mirror.
//
//  What goes in the queue (idempotent driver mutations only):
//
//      • changeHosStatus   — §395 duty-status transition (legal event)
//      • sendMessage       — chat / dispatcher ping
//      • submitPOD         — proof of delivery at the receiver
//      • executeTransition — load lifecycle flip (arrived / picked up / …)
//      • acceptLoad        — driver takes ownership of an offered load
//      • geofenceEvent     — facility fence ENTER/EXIT (ON-SITE / departed
//                            flip + detention clock; dead zones at the dock
//                            must not lose it)
//
//  What NEVER goes in the queue:
//
//      • reads (a stale read is harmless; just refetch when back online)
//      • money mutations (payout / escrow / P2P transfer) — replaying a
//        debit hours later, out of the user's sight, is a financial-
//        integrity footgun. Those stay strictly online-only and surface
//        a hard error when offline.
//
//  Each entry carries the minimal payload + an idempotency key, minted at
//  enqueue and sent to the server on replay (as the optional
//  `idempotencyKey` input field) so a replay that races a manual retry
//  (or a duplicate flush) doesn't double-apply. The key is honored two
//  ways, depending on the proc:
//
//      • sendMessage + submitPOD are record-creating — the server dedupes
//        on (userId + idempotencyKey) and returns the prior result
//        instead of inserting a duplicate row.
//      • changeHosStatus + executeTransition + acceptLoad are naturally
//        idempotent via the server's duty-status / FSM state guards
//        (re-applying an already-applied state is a no-op); they accept
//        the key only so its Zod schema doesn't strip/reject it.
//
//  The keys are stable across persistence — they survive an app kill /
//  cold relaunch, which is the whole point: a driver who flips ON-DUTY in
//  a dead spot, force-quits, and relaunches in coverage still gets that
//  legal event up to the server, exactly once.
//
//  Reachability: there is no shared phone-wide network monitor today
//  (only a local one inside 364_OfflineBanner), so — exactly like the
//  wrist, whose `NetworkReachabilityHub` is bundled in this same file —
//  we ship a singleton `NWPathMonitor` hub here that fires `flush()` on
//  the .unsatisfied → .satisfied edge. EusoTripApp starts it once at
//  launch.
//

import Foundation
import Combine
import Network

// MARK: - QueuedAction

/// One durable, idempotent driver mutation awaiting replay.
///
/// Deliberately a closed set — only the five enqueue-eligible driver
/// mutations are representable. Reads and money mutations have no case
/// here, so they physically cannot enter the outbox.
enum QueuedAction: Codable, Equatable {
    /// §395 duty-status transition. `status` is the `HOSDutyCode.rawValue`
    /// the server expects ("off_duty" | "sleeper" | "driving" | "on_duty").
    case changeHosStatus(status: String, location: String, remark: String?, loadId: String?, at: Date, key: String)
    /// Chat / dispatcher message on an existing conversation.
    case sendMessage(conversationId: String, content: String, type: String, at: Date, key: String)
    /// Proof of delivery at the receiver.
    case submitPOD(loadId: Int, receiverName: String, photoBase64: String?, signatureBase64: String?, notes: String?, at: Date, key: String)
    /// Load-lifecycle state flip (arrived / picked up / delivered / …).
    case executeTransition(loadId: String, transitionId: String, at: Date, key: String)
    /// Driver takes ownership of an offered load.
    case acceptLoad(loadId: String, at: Date, key: String)
    /// Facility geofence crossing (ENTER/EXIT) — carries the original fix +
    /// timestamp so a dead-zone crossing replays with its true wall-clock
    /// time. Naturally idempotent: the server FSM transition guard makes a
    /// re-applied status flip a no-op.
    case geofenceEvent(geofenceId: Int, action: String, lat: Double, lng: Double,
                       timestamp: String, loadId: Int?, geofenceType: String?,
                       at: Date, key: String)

    /// Stable idempotency key — generated at enqueue, persisted, and
    /// echoed to the server so a re-send collapses instead of duplicating.
    var key: String {
        switch self {
        case .changeHosStatus(_, _, _, _, _, let k): return k
        case .sendMessage(_, _, _, _, let k):        return k
        case .submitPOD(_, _, _, _, _, _, let k):    return k
        case .executeTransition(_, _, _, let k):     return k
        case .acceptLoad(_, _, let k):               return k
        case .geofenceEvent(_, _, _, _, _, _, _, _, let k): return k
        }
    }

    /// Enqueue timestamp — drives causal replay order.
    var enqueuedAt: Date {
        switch self {
        case .changeHosStatus(_, _, _, _, let at, _): return at
        case .sendMessage(_, _, _, let at, _):        return at
        case .submitPOD(_, _, _, _, _, let at, _):    return at
        case .executeTransition(_, _, let at, _):     return at
        case .acceptLoad(_, let at, _):               return at
        case .geofenceEvent(_, _, _, _, _, _, _, let at, _): return at
        }
    }

    /// Short human label for the (future) outbox inspector UI.
    var label: String {
        switch self {
        case .changeHosStatus:   return "Duty status"
        case .sendMessage:       return "Message"
        case .submitPOD:         return "Proof of delivery"
        case .executeTransition: return "Load update"
        case .acceptLoad:        return "Load accept"
        case .geofenceEvent:     return "Arrival update"
        }
    }
}

// MARK: - OfflineQueue

@MainActor
final class OfflineQueue: ObservableObject {
    static let shared = OfflineQueue()

    /// Pending actions awaiting replay, oldest-first. Persisted across
    /// app launches. Consumers (e.g. an outbox badge) bind to this.
    @Published private(set) var pending: [QueuedAction] = []

    /// True while a `flush()` pass is in flight — keeps the path monitor
    /// edge and a manual flush from stomping on each other.
    @Published private(set) var isFlushing: Bool = false

    /// File-backed persistence in Application Support so queued actions
    /// survive a cold relaunch (the dead-spot → force-quit → coverage
    /// path that the whole feature exists for).
    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("eusotrip_offline_outbox.json")
    }()

    private init() {
        restore()
    }

    // MARK: Persistence

    private struct Envelope: Codable {
        var version: Int
        var actions: [QueuedAction]
    }

    /// Load the persisted queue on first access. Tolerant: a missing /
    /// corrupt file just yields an empty queue rather than throwing.
    private func restore() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let env = try? JSONDecoder().decode(Envelope.self, from: data) {
            pending = env.actions.sorted { $0.enqueuedAt < $1.enqueuedAt }
        }
    }

    private func persist() {
        let env = Envelope(version: 1, actions: pending)
        if let data = try? JSONEncoder().encode(env) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func key() -> String { UUID().uuidString }

    // MARK: Enqueue
    //
    // Each enqueue returns the idempotency key it minted so the caller
    // can correlate an optimistic UI bubble with the queued action and
    // reconcile it on replay (DriverConversationView does this for chat).

    @discardableResult
    func enqueueChangeHosStatus(status: String, location: String, remark: String?, loadId: String?) -> String {
        let k = key()
        append(.changeHosStatus(status: status, location: location, remark: remark, loadId: loadId, at: Date(), key: k))
        return k
    }

    @discardableResult
    func enqueueSendMessage(conversationId: String, content: String, type: String = "text") -> String {
        let k = key()
        append(.sendMessage(conversationId: conversationId, content: content, type: type, at: Date(), key: k))
        return k
    }

    @discardableResult
    func enqueueSubmitPOD(loadId: Int, receiverName: String, photoBase64: String?, signatureBase64: String?, notes: String?) -> String {
        let k = key()
        append(.submitPOD(loadId: loadId, receiverName: receiverName, photoBase64: photoBase64, signatureBase64: signatureBase64, notes: notes, at: Date(), key: k))
        return k
    }

    @discardableResult
    func enqueueExecuteTransition(loadId: String, transitionId: String) -> String {
        let k = key()
        append(.executeTransition(loadId: loadId, transitionId: transitionId, at: Date(), key: k))
        return k
    }

    @discardableResult
    func enqueueAcceptLoad(loadId: String) -> String {
        let k = key()
        append(.acceptLoad(loadId: loadId, at: Date(), key: k))
        return k
    }

    @discardableResult
    func enqueueGeofenceEvent(geofenceId: Int, action: String, lat: Double, lng: Double,
                              timestamp: String, loadId: Int?, geofenceType: String?) -> String {
        let k = key()
        append(.geofenceEvent(geofenceId: geofenceId, action: action, lat: lat, lng: lng,
                              timestamp: timestamp, loadId: loadId, geofenceType: geofenceType,
                              at: Date(), key: k))
        return k
    }

    private func append(_ action: QueuedAction) {
        pending.append(action)
        pending.sort { $0.enqueuedAt < $1.enqueuedAt }
        persist()
    }

    // MARK: Inspection helpers

    var count: Int { pending.count }
    var isEmpty: Bool { pending.isEmpty }

    func contains(key: String) -> Bool {
        pending.contains { $0.key == key }
    }

    /// Idempotency key of the newest pending `sendMessage` matching this
    /// conversation + content, so a caller that staged an optimistic
    /// bubble (DriverConversationView) can link it to the queued action
    /// and reconcile when `.eusoOutboxReplayed` fires. Returns nil when
    /// no match is pending.
    func keyForPendingMessage(conversationId: String, content: String) -> String? {
        for action in pending.reversed() {
            if case let .sendMessage(cid, body, _, _, k) = action,
               cid == conversationId, body == content {
                return k
            }
        }
        return nil
    }

    // MARK: Flush / replay
    //
    // Replays queued actions against the live EusoTripAPI, oldest-first.
    // A success removes the entry; a still-offline failure leaves the
    // entry in place to retry on the next edge (we break the pass so a
    // dead endpoint doesn't burn the whole queue). A *non-network*
    // failure (e.g. a server-rejected transition) also removes the entry
    // — replaying it forever would never succeed, and the idempotency
    // key already guards against a double-apply if it actually landed.

    /// Public alias mirroring the wrist's `flushAll`. Safe to call any
    /// time — no-ops when the queue is empty or no bearer is set.
    func replay() async { await flush() }

    func flush() async {
        guard !isFlushing else { return }
        guard EusoTripAPI.shared.authToken != nil else { return }
        guard !pending.isEmpty else { return }

        isFlushing = true
        defer { isFlushing = false }

        // Snapshot in causal order. Re-read `pending` each iteration so a
        // concurrent enqueue mid-flush is picked up next pass, not now.
        let snapshot = pending.sorted { $0.enqueuedAt < $1.enqueuedAt }
        for action in snapshot {
            // Skip anything already drained by a racing pass.
            guard pending.contains(where: { $0.key == action.key }) else { continue }
            do {
                try await replay(action)
                remove(key: action.key)
                // Let interested surfaces re-pull (the conversation view
                // reconciles its queued bubble, the load board refreshes).
                NotificationCenter.default.post(
                    name: .eusoOutboxReplayed,
                    object: nil,
                    userInfo: ["key": action.key]
                )
            } catch {
                if Self.isNetworkUnreachable(error) {
                    // Still offline — stop the pass, keep the entry, retry
                    // on the next satisfied edge.
                    break
                } else {
                    // A real server-side rejection. Don't loop on it
                    // forever; drop it (the idempotency key already
                    // protects against a double-apply if it half-landed).
                    #if DEBUG
                    print("[OfflineQueue] dropping \(action.label) after non-network failure: \(error)")
                    #endif
                    remove(key: action.key)
                    NotificationCenter.default.post(
                        name: .eusoOutboxReplayFailed,
                        object: nil,
                        userInfo: ["key": action.key]
                    )
                }
            }
        }
        persist()
    }

    private func remove(key: String) {
        pending.removeAll { $0.key == key }
    }

    /// Dispatch one queued action to its real EusoTripAPI method, passing
    /// the action's stored idempotency key through to the server so a
    /// replay collapses instead of double-applying:
    ///
    ///   • `sendMessage` / `submitPOD` are record-creating — the server
    ///     dedupes on (userId + idempotencyKey) and returns the prior
    ///     result instead of inserting a duplicate.
    ///   • `changeHosStatus` / `executeTransition` / `acceptLoad` are
    ///     naturally idempotent via the server's FSM / duty-status state
    ///     guards (re-applying an already-applied state is a no-op); they
    ///     accept the key only so its Zod schema doesn't strip/reject it.
    ///
    /// The key is minted at enqueue and persisted, so it is stable across
    /// an app kill / cold relaunch — the same key reaches the server on
    /// the first replay and on any racing manual retry.
    private func replay(_ action: QueuedAction) async throws {
        let api = EusoTripAPI.shared
        switch action {
        case .changeHosStatus(let status, let location, let remark, let loadId, _, let key):
            let code = HOSDutyCode(rawValue: status) ?? .offDuty
            _ = try await api.hos.changeStatus(
                status: code,
                source: "ios-offline",
                location: location,
                remark: remark,
                loadId: loadId,
                idempotencyKey: key
            )
        case .sendMessage(let conversationId, let content, let type, _, let key):
            _ = try await api.messaging.sendMessage(
                conversationId: conversationId,
                content: content,
                type: type,
                idempotencyKey: key
            )
        case .submitPOD(let loadId, let receiverName, let photoBase64, let signatureBase64, let notes, _, let key):
            _ = try await api.pod.submitPOD(
                loadId: loadId,
                receiverName: receiverName,
                photoBase64: photoBase64,
                signatureBase64: signatureBase64,
                notes: notes,
                idempotencyKey: key
            )
        case .executeTransition(let loadId, let transitionId, _, let key):
            _ = try await api.loadLifecycle.executeTransition(
                loadId: loadId,
                transitionId: transitionId,
                idempotencyKey: key
            )
        case .acceptLoad(let loadId, _, let key):
            _ = try await api.drivers.acceptLoad(loadId: loadId, idempotencyKey: key)
        case .geofenceEvent(let geofenceId, let action, let lat, let lng,
                            let timestamp, let loadId, let geofenceType, _, _):
            // Replays with the ORIGINAL crossing timestamp so detention math
            // stays honest. Naturally idempotent server-side (FSM guard).
            try await api.trackingGeofences.postGeofenceEvent(
                geofenceId: geofenceId, action: action, lat: lat, lng: lng,
                timestamp: timestamp, loadId: loadId,
                geofenceType: geofenceType, facilityName: nil)
        }
    }

    // MARK: Network-error classification
    //
    // Shared by the queue (decide whether to retry vs. drop) and by the
    // EusoTripAPI mutation path (decide whether to enqueue at all). The
    // canonical "you're offline" URL errors: not-connected, connection
    // lost, can't-connect-to-host, timed-out, DNS lookup failed.

    nonisolated static func isNetworkUnreachable(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        switch ns.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorCannotFindHost,
             NSURLErrorDNSLookupFailed,
             NSURLErrorTimedOut,
             NSURLErrorInternationalRoamingOff,
             NSURLErrorDataNotAllowed:
            return true
        default:
            return false
        }
    }
}

// MARK: - Outbox notifications

extension Notification.Name {
    /// Posted after a queued action replays successfully. `userInfo["key"]`
    /// is the idempotency key. Surfaces that staged an optimistic bubble
    /// (DriverConversationView) reconcile against it.
    static let eusoOutboxReplayed = Notification.Name("eusoOutboxReplayed")
    /// Posted when a queued action is dropped after a non-network failure.
    static let eusoOutboxReplayFailed = Notification.Name("eusoOutboxReplayFailed")
}

// MARK: - Reachability drain
//
// Mirror of the wrist's `NetworkReachabilityHub`. The phone has no
// shared network monitor today (only a local one inside the
// 364_OfflineBanner screen), so we ship the singleton here and fire
// `flush()` on the .unsatisfied → .satisfied edge. Start it once from
// EusoTripApp at launch.

@MainActor
final class OfflineReachabilityHub: ObservableObject {
    static let shared = OfflineReachabilityHub()

    /// Last-known path satisfaction — observable so a banner can read it.
    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.eusotrip.phone.outbox.net", qos: .utility)
    private var started = false
    private var lastSatisfied = true

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = satisfied
                // Edge-trigger: only flush on the transition back online.
                let edge = satisfied && !self.lastSatisfied
                self.lastSatisfied = satisfied
                if edge {
                    await OfflineQueue.shared.flush()
                }
            }
        }
        monitor.start(queue: queue)
    }
}
