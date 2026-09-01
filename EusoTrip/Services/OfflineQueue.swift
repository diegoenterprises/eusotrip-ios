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
//      • postHaulMessage   — moderated global Haul-lobby message
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
/// Deliberately a closed set — only explicitly enqueue-eligible driver
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
    /// Global, moderated Haul-lobby post. The server deduplicates this key
    /// inside the authenticated user's scope before rate limiting.
    case postHaulMessage(message: String, ownerUserId: String?, at: Date, key: String)

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
        case .postHaulMessage(_, _, _, let k):               return k
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
        case .postHaulMessage(_, _, let at, _):               return at
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
        case .postHaulMessage:   return "Haul message"
        }
    }
}

enum OfflineQueueStorageError: LocalizedError {
    case writeFailed
    case readFailed
    case deliveryIdentityConflict
    case emptyHaulDraft
    case sessionIdentityUnavailable
    case deliveryOwnerMismatch

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            return "This message is still in the composer because EusoTrip could not secure it for offline delivery. Free device storage, then try again."
        case .readFailed:
            return "EusoTrip could not read the saved Haul drafts on this device. The original outbox has not been discarded."
        case .deliveryIdentityConflict:
            return "This delivery identity already belongs to different Haul text. Keep the draft and send it as a new message."
        case .emptyHaulDraft:
            return "Enter a message before queuing it for the Haul."
        case .sessionIdentityUnavailable:
            return "Your signed-in identity could not be verified, so this Haul message was not queued. Keep the draft and sign in again."
        case .deliveryOwnerMismatch:
            return "This saved Haul message belongs to a different signed-in account and was not posted."
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

    /// Non-nil when the persisted envelope exists but cannot be read. The
    /// original file remains untouched and all subsequent persistence fails
    /// closed so unknown queued work cannot be replaced by an empty envelope.
    @Published private(set) var storageError: String?

    /// True while a `flush()` pass is in flight — keeps the path monitor
    /// edge and a manual flush from stomping on each other.
    @Published private(set) var isFlushing: Bool = false
    private var scheduledRetry: Task<Void, Never>?

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

    /// Load the persisted queue on first access. A missing file is a truthful
    /// empty queue. An unreadable or corrupt file is not: preserve it and
    /// expose the fault so the Haul composer can retain the user's draft.
    private func restore() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            pending = env.actions.sorted { $0.enqueuedAt < $1.enqueuedAt }
            storageError = nil
        } catch {
            storageError = OfflineQueueStorageError.readFailed.localizedDescription
        }
    }

    private func persist(actions: [QueuedAction]) throws {
        guard storageError == nil else {
            throw OfflineQueueStorageError.readFailed
        }
        do {
            let env = Envelope(version: 1, actions: actions)
            let data = try JSONEncoder().encode(env)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            throw OfflineQueueStorageError.writeFailed
        }
    }

    private func persist() {
        do {
            try persist(actions: pending)
        } catch {
            NotificationCenter.default.post(
                name: .eusoOutboxStorageFailed,
                object: nil,
                userInfo: ["reason": error.localizedDescription]
            )
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

    @discardableResult
    func enqueueHaulMessage(message: String, idempotencyKey: String? = nil) throws -> String {
        guard storageError == nil else { throw OfflineQueueStorageError.readFailed }
        guard let ownerUserId = currentHaulOwnerUserId() else {
            throw OfflineQueueStorageError.sessionIdentityUnavailable
        }
        let k = idempotencyKey ?? key()
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OfflineQueueStorageError.emptyHaulDraft }
        if let existing = pending.first(where: { $0.key == k }) {
            if case let .postHaulMessage(existingMessage, existingOwnerUserId, _, _) = existing,
               existingMessage == trimmed,
               existingOwnerUserId == ownerUserId {
                return k
            }
            throw OfflineQueueStorageError.deliveryIdentityConflict
        }
        var next = pending
        next.append(.postHaulMessage(
            message: trimmed,
            ownerUserId: ownerUserId,
            at: Date(),
            key: k
        ))
        next.sort { $0.enqueuedAt < $1.enqueuedAt }
        try persist(actions: next)
        pending = next
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

    func keyForPendingHaulMessage(content: String) -> String? {
        guard let ownerUserId = currentHaulOwnerUserId() else { return nil }
        for action in pending.reversed() {
            if case let .postHaulMessage(body, actionOwnerUserId, _, key) = action,
               body == content,
               actionOwnerUserId == ownerUserId {
                return key
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

    /// A provider can be temporarily unavailable while the phone still has a
    /// healthy network path. Reachability will not emit a reconnect edge in
    /// that case, so schedule a bounded replay instead of leaving the action
    /// parked until the next radio transition.
    func scheduleReplay(after delay: TimeInterval = 4) {
        guard scheduledRetry == nil, OfflineReachabilityHub.shared.isOnline else { return }
        let bounded = min(max(delay, 1), 60)
        scheduledRetry = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(bounded * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.scheduledRetry = nil
            await self.flush()
            if !self.pending.isEmpty, OfflineReachabilityHub.shared.isOnline {
                self.scheduleReplay(after: min(bounded * 2, 60))
            }
        }
    }

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
            if case let .postHaulMessage(_, ownerUserId, _, _) = action {
                // A device can change accounts while an outbox survives. Never
                // replay Account A's community post under Account B's bearer.
                // Legacy entries without ownership stay quarantined in place.
                guard let currentOwnerUserId = currentHaulOwnerUserId(),
                      ownerUserId == currentOwnerUserId
                else { continue }
            }
            do {
                try await replay(action)
                if case .postHaulMessage = action {
                    try discardFailedHaulDraft(key: action.key)
                    try removeDurably(key: action.key)
                } else {
                    remove(key: action.key)
                }
                // Let interested surfaces re-pull (the conversation view
                // reconciles its queued bubble, the load board refreshes).
                NotificationCenter.default.post(
                    name: .eusoOutboxReplayed,
                    object: nil,
                    userInfo: ["key": action.key]
                )
            } catch {
                if error is OfflineQueueStorageError {
                    NotificationCenter.default.post(
                        name: .eusoOutboxStorageFailed,
                        object: nil,
                        userInfo: [
                            "key": action.key,
                            "reason": error.localizedDescription,
                        ]
                    )
                    scheduleReplay()
                    continue
                } else if Self.isNetworkUnreachable(error) {
                    // Still offline — stop the pass, keep the entry, retry
                    // on the next satisfied edge.
                    break
                } else if Self.isRetryableFailure(error) {
                    // The phone is online but this service is temporarily
                    // unavailable (5xx, lock timeout, rate limit, etc.). Keep
                    // the original durable action and stable key. Continue the
                    // pass so a Haul outage cannot block a legal HOS/POD event,
                    // then retry the retained action on a bounded backoff.
                    scheduleReplay()
                    continue
                } else {
                    // A real server-side rejection. Don't loop on it
                    // forever; drop it (the idempotency key already
                    // protects against a double-apply if it half-landed).
                    #if DEBUG
                    print("[OfflineQueue] dropping \(action.label) after non-network failure: \(error)")
                    #endif
                    if case let .postHaulMessage(message, ownerUserId, _, key) = action {
                        do {
                            try stageHaulDraftForRecovery(
                                message: message,
                                key: key,
                                ownerUserId: ownerUserId
                            )
                            try removeDurably(key: action.key)
                        } catch {
                            NotificationCenter.default.post(
                                name: .eusoOutboxStorageFailed,
                                object: nil,
                                userInfo: [
                                    "key": action.key,
                                    "reason": error.localizedDescription,
                                ]
                            )
                            scheduleReplay()
                            continue
                        }
                    } else {
                        remove(key: action.key)
                    }
                    NotificationCenter.default.post(
                        name: .eusoOutboxReplayFailed,
                        object: nil,
                        userInfo: [
                            "key": action.key,
                            "message": recoverableMessage(in: action) as Any,
                            "reason": error.localizedDescription,
                        ]
                    )
                }
            }
        }
        persist()
    }

    private func remove(key: String) {
        pending.removeAll { $0.key == key }
    }

    private func removeDurably(key: String) throws {
        let next = pending.filter { $0.key != key }
        try persist(actions: next)
        pending = next
    }

    struct FailedHaulDraft: Codable, Equatable {
        let key: String
        let message: String
        let ownerUserId: String?
        let failedAt: Date
    }

    /// Separate recovery file for terminally rejected Haul posts. It is an
    /// array, not a single preference value, so two moderation decisions in
    /// one replay pass cannot overwrite each other. Entries remain here until
    /// the composer successfully sends or requeues that exact key.
    private let failedHaulURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("eusotrip_failed_haul_drafts.json")
    }()

    private func failedHaulDrafts() throws -> [FailedHaulDraft] {
        guard FileManager.default.fileExists(atPath: failedHaulURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: failedHaulURL)
            let drafts = try JSONDecoder().decode([FailedHaulDraft].self, from: data)
            return drafts.sorted { $0.failedAt < $1.failedAt }
        } catch {
            throw OfflineQueueStorageError.readFailed
        }
    }

    private func persistFailedHaulDrafts(_ drafts: [FailedHaulDraft]) throws {
        do {
            let data = try JSONEncoder().encode(drafts)
            try data.write(to: failedHaulURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            throw OfflineQueueStorageError.writeFailed
        }
    }

    /// Persist the exact text and delivery UUID before an online write starts.
    /// If the app is killed after the server commits but before the response
    /// arrives, the next launch restores this same pair and the server resolves
    /// it to the original row instead of inserting a duplicate.
    func stageHaulDraftForRecovery(
        message: String,
        key: String,
        ownerUserId requestedOwnerUserId: String? = nil
    ) throws {
        guard let currentOwnerUserId = currentHaulOwnerUserId() else {
            throw OfflineQueueStorageError.sessionIdentityUnavailable
        }
        let ownerUserId = requestedOwnerUserId ?? currentOwnerUserId
        guard ownerUserId == currentOwnerUserId else {
            throw OfflineQueueStorageError.deliveryOwnerMismatch
        }
        let canonical = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { throw OfflineQueueStorageError.emptyHaulDraft }
        var drafts = try failedHaulDrafts()
        if let existing = drafts.first(where: { $0.key == key }) {
            guard existing.message == canonical,
                  existing.ownerUserId == ownerUserId
            else {
                throw OfflineQueueStorageError.deliveryIdentityConflict
            }
            return
        }
        drafts.append(FailedHaulDraft(
            key: key,
            message: canonical,
            ownerUserId: ownerUserId,
            failedAt: Date()
        ))
        try persistFailedHaulDrafts(drafts)
    }

    func firstFailedHaulDraft() throws -> FailedHaulDraft? {
        guard let ownerUserId = currentHaulOwnerUserId() else {
            throw OfflineQueueStorageError.sessionIdentityUnavailable
        }
        return try failedHaulDrafts().first { $0.ownerUserId == ownerUserId }
    }

    func failedHaulDraft(key: String) throws -> FailedHaulDraft? {
        guard let ownerUserId = currentHaulOwnerUserId() else {
            throw OfflineQueueStorageError.sessionIdentityUnavailable
        }
        return try failedHaulDrafts().first {
            $0.key == key && $0.ownerUserId == ownerUserId
        }
    }

    func discardFailedHaulDraft(key: String) throws {
        guard let ownerUserId = currentHaulOwnerUserId() else {
            throw OfflineQueueStorageError.sessionIdentityUnavailable
        }
        let drafts = try failedHaulDrafts()
        guard drafts.contains(where: { $0.key == key && $0.ownerUserId == ownerUserId }) else { return }
        try persistFailedHaulDrafts(drafts.filter {
            !($0.key == key && $0.ownerUserId == ownerUserId)
        })
    }

    private func recoverableMessage(in action: QueuedAction) -> String? {
        if case let .postHaulMessage(message, ownerUserId, _, _) = action,
           ownerUserId == currentHaulOwnerUserId() {
            return message
        }
        return nil
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
            guard let code = HOSDutyCode(rawValue: status) else {
                throw EusoTripAPIError.decodingFailed(
                    "Queued HOS event contains an unsupported duty status"
                )
            }
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
        case .postHaulMessage(let message, let ownerUserId, _, let key):
            guard let currentOwnerUserId = currentHaulOwnerUserId(),
                  ownerUserId == currentOwnerUserId
            else {
                throw OfflineQueueStorageError.deliveryOwnerMismatch
            }
            let result = try await api.gamification.postLobbyMessage(
                message: message,
                idempotencyKey: key
            )
            guard result.success else {
                throw EusoTripAPIError.trpcError(result.error ?? "The Haul rejected this message.")
            }
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

    /// The JWT has already been signature-verified by the server before any
    /// write can commit. Locally we decode only its stable numeric userId to
    /// partition device recovery state; this value never grants authority.
    private func currentHaulOwnerUserId() -> String? {
        Self.haulOwnerUserId(from: EusoTripAPI.shared.authToken)
    }

    nonisolated private static func haulOwnerUserId(from token: String?) -> String? {
        guard let token else { return nil }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let rawUserId: String?
        if let value = object["userId"] as? String {
            rawUserId = value
        } else if let value = object["userId"] as? NSNumber {
            rawUserId = value.stringValue
        } else {
            rawUserId = nil
        }
        guard let rawUserId,
              let numericUserId = Int(rawUserId),
              numericUserId > 0
        else { return nil }
        return String(numericUserId)
    }

    /// Infrastructure and throttling failures are continuation states, not
    /// terminal outcomes. These stay in the durable queue with the same key.
    nonisolated static func isRetryableFailure(_ error: Error) -> Bool {
        if isNetworkUnreachable(error) { return true }
        guard let apiError = error as? EusoTripAPIError else { return false }
        switch apiError {
        case .httpStatus(let status, _):
            return status == 408 || status == 425 || status == 429 || status >= 500
        case .trpcError(let message):
            return isRetryableServerMessage(message)
        case .queuedForOfflineReplay:
            return true
        default:
            return false
        }
    }

    nonisolated static func isRetryableServerMessage(_ message: String) -> Bool {
        let value = message.lowercased()
        return value.contains("reconnecting")
            || value.contains("delivery was not confirmed")
            || value.contains("temporarily unavailable")
            || value.contains("service unavailable")
            || value.contains("retry in a moment")
            || value.contains("try again in a moment")
            || value.contains("please wait a moment before posting again")
            || value.contains("rate limit")
            || value.contains("too many requests")
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
    /// Posted when a local outbox transition could not be atomically persisted.
    /// The queued action remains intact and must not be presented as sent.
    static let eusoOutboxStorageFailed = Notification.Name("eusoOutboxStorageFailed")
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
