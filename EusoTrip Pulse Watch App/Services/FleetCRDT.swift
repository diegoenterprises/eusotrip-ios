//
//  FleetCRDT.swift
//  EusoTrip Pulse Watch App
//
//  Q3 2026 offline-mode tier — per-field vector-clock Last-Writer-Wins
//  conflict-free replicated data type for HOS + active-load state.
//
//  The hard problem:
//    Two devices both hold a copy of the driver's HOS + active load.
//    Either can mutate any field while offline (the driver flips to
//    sleeper-berth on the wrist; dispatch reassigns the load on the
//    iOS app while the driver's watch is out of range). When both
//    devices reconnect, we need a deterministic merge that:
//      • Never loses a mutation silently.
//      • Never requires the user to resolve a conflict manually.
//      • Preserves causality: if two mutations are causally ordered,
//        the later one wins even if it arrived at the server first.
//
//  Shape:
//    Each mutable field is tagged with `(actorId, vectorClock, value)`.
//    On merge: for each field, compare vector clocks. Concurrent writes
//    → resolve by stable hash of actorId (deterministic across both
//    sides without a coordinator).
//
//  This scaffold implements the generic CRDT + wires HOS status as the
//  first field. Load state joins in a follow-up.
//

import Foundation
import Combine

/// Opaque actor identifier — the combined (deviceId, driverId) string.
typealias CRDTActor = String

/// Sparse vector clock: actor → event count. Missing entries are 0.
struct VectorClock: Codable, Equatable, Hashable {
    private(set) var counts: [CRDTActor: UInt64]

    init(_ counts: [CRDTActor: UInt64] = [:]) { self.counts = counts }

    mutating func tick(_ actor: CRDTActor) {
        counts[actor, default: 0] += 1
    }

    /// Returns the strictly later clock, or nil if concurrent.
    func compare(_ other: VectorClock) -> ComparisonResult? {
        var leftDominates = false
        var rightDominates = false
        let keys = Set(counts.keys).union(other.counts.keys)
        for k in keys {
            let a = counts[k, default: 0]
            let b = other.counts[k, default: 0]
            if a > b { leftDominates = true }
            if b > a { rightDominates = true }
        }
        switch (leftDominates, rightDominates) {
        case (false, false): return .orderedSame
        case (true, false):  return .orderedDescending
        case (false, true):  return .orderedAscending
        case (true, true):   return nil // concurrent
        }
    }

    mutating func merge(_ other: VectorClock) {
        for (k, v) in other.counts {
            counts[k] = max(counts[k, default: 0], v)
        }
    }
}

/// A single field tagged with its last writer + vector clock.
struct CRDTField<Value: Codable & Equatable>: Codable, Equatable {
    var value: Value
    var actor: CRDTActor
    var clock: VectorClock
    var ts: Date

    /// LWW merge. Prefers causally later; on concurrent, picks the
    /// field whose actor has the lower (stable) hash. This is
    /// deterministic across devices so both sides arrive at the same
    /// state without a coordinator.
    func merged(with other: CRDTField<Value>) -> CRDTField<Value> {
        switch clock.compare(other.clock) {
        case .orderedDescending:
            return self
        case .orderedAscending:
            return other
        case .orderedSame:
            return self // identical; pick either
        case .none:
            // Concurrent — break tie deterministically.
            if actor.hashValue <= other.actor.hashValue { return self }
            return other
        }
    }
}

/// HOS CRDT snapshot — the minimum fields the driver can mutate offline.
struct HOSCRDTState: Codable, Equatable {
    var status:           CRDTField<String>
    var driveMinutes:     CRDTField<Int>
    var windowMinutes:    CRDTField<Int>
    var cycleMinutes:     CRDTField<Int>
    var statusSince:      CRDTField<Date>

    func merged(with other: HOSCRDTState) -> HOSCRDTState {
        HOSCRDTState(
            status:        status.merged(with: other.status),
            driveMinutes:  driveMinutes.merged(with: other.driveMinutes),
            windowMinutes: windowMinutes.merged(with: other.windowMinutes),
            cycleMinutes:  cycleMinutes.merged(with: other.cycleMinutes),
            statusSince:   statusSince.merged(with: other.statusSince)
        )
    }
}

/// Active-load CRDT snapshot — the fields the driver + dispatcher can
/// both mutate offline. We deliberately keep the surface narrow:
///   • `lifecycle`   — the canonical TripEvent-style state machine string
///                     ("accepted", "at_pickup", "loaded",
///                     "at_dropoff", "unloaded", "pod_pending",
///                     "pod_uploaded", "completed"). Merge via LWW —
///                     the later-clock writer wins. Concurrent writes
///                     (rare; requires both sides offline while
///                     mutating) resolve via the stable actor-hash
///                     tie-break in `CRDTField.merged`, which for
///                     lifecycle means "deterministic but arbitrary."
///                     Server is the source of truth on reconnect and
///                     will reconcile via `trajectory.ledgerReconcile`.
///   • `assignedDriverId` — reassignment edge case. Rare but real;
///                     dispatch may reassign while the wrist is offline.
///   • `estimatedArrivalAt` — last locally-computed ETA. Used by the UI
///                     until the server returns a fresher one.
///   • `podUploaded` — a boolean flag that flips true once we've pushed
///                     the POD. Monotonic (never flips back to false),
///                     so LWW is safe.
///   • `notes`       — free-text pin the driver can jot ("trailer door
///                     won't close"). LWW; collisions unlikely in
///                     practice because only the driver writes this
///                     field.
struct LoadCRDTState: Codable, Equatable {
    var loadId:             String
    var lifecycle:          CRDTField<String>
    var assignedDriverId:   CRDTField<String>
    var estimatedArrivalAt: CRDTField<Date>
    var podUploaded:        CRDTField<Bool>
    var notes:              CRDTField<String>

    func merged(with other: LoadCRDTState) -> LoadCRDTState {
        // Guard against peer snapshots for a different loadId landing
        // in our merge — prefer local if the IDs don't agree.
        guard loadId == other.loadId else { return self }
        return LoadCRDTState(
            loadId:             loadId,
            lifecycle:          lifecycle.merged(with: other.lifecycle),
            assignedDriverId:   assignedDriverId.merged(with: other.assignedDriverId),
            estimatedArrivalAt: estimatedArrivalAt.merged(with: other.estimatedArrivalAt),
            podUploaded:        podUploaded.merged(with: other.podUploaded),
            notes:              notes.merged(with: other.notes)
        )
    }
}

/// Entry point for other modules. Wraps HOS + active-Load CRDT state
/// behind a simple "mutate this field" API that handles vector-clock
/// bookkeeping. All mutations tick the local clock once, so per-field
/// causality stays well-defined even when multiple fields update in
/// the same wall-clock second.
@MainActor
final class FleetCRDT: ObservableObject {
    static let shared = FleetCRDT()

    @Published private(set) var hos: HOSCRDTState?
    /// Keyed by `loadId` — a driver might rotate between loads in a
    /// single shift, so we keep per-load snapshots around. The "active"
    /// load (`LoadStore.shared.active?.id`) is what the UI usually
    /// binds to, but the dictionary is the source of truth for merges.
    @Published private(set) var loads: [String: LoadCRDTState] = [:]

    private var clock = VectorClock()
    private var actor: CRDTActor = "pulse-unpaired"

    /// Called once on launch with a stable device + driver identity.
    /// Uses a UserDefaults-persisted device UUID so the actor id is
    /// stable across app launches — without that, every cold start
    /// would generate a new actor id and the vector clock would
    /// inflate without bound, eventually defeating the LWW tie-break.
    /// Migrates to Keychain in a later drop; for now UserDefaults on
    /// the watch's group container is acceptable since the actor id
    /// is non-sensitive and the backend signs all merged writes.
    func configure(driverId: String) {
        let deviceIdKey = "com.eusotrip.crdt.deviceId"
        let defaults = UserDefaults.standard
        let deviceId: String
        if let existing = defaults.string(forKey: deviceIdKey), !existing.isEmpty {
            deviceId = existing
        } else {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: deviceIdKey)
            deviceId = fresh
        }
        actor = "\(driverId):\(deviceId)"
    }

    /// Seed the HOS CRDT snapshot. Safe to call multiple times — a later
    /// seed overwrites an earlier one only if the CRDT is still empty,
    /// so a restore() or a remote ingest can't stomp on live mutations.
    func seedIfEmpty(
        status: String,
        driveMinutes: Int,
        windowMinutes: Int,
        cycleMinutes: Int,
        statusSince: Date
    ) {
        guard hos == nil else { return }
        clock.tick(actor)
        let seedClock = clock
        let seedActor = actor
        let now = Date()
        hos = HOSCRDTState(
            status:        CRDTField(value: status,        actor: seedActor, clock: seedClock, ts: now),
            driveMinutes:  CRDTField(value: driveMinutes,  actor: seedActor, clock: seedClock, ts: now),
            windowMinutes: CRDTField(value: windowMinutes, actor: seedActor, clock: seedClock, ts: now),
            cycleMinutes:  CRDTField(value: cycleMinutes,  actor: seedActor, clock: seedClock, ts: now),
            statusSince:   CRDTField(value: statusSince,   actor: seedActor, clock: seedClock, ts: now)
        )
    }

    /// Mutate a single field locally. Bumps the clock and re-publishes.
    /// If the CRDT isn't seeded yet, promotes the very first mutation
    /// site into a lazy seed so `HOSStore` can safely fire mutations
    /// without coordinating the seed/mutate ordering at launch.
    func mutate<V>(_ keyPath: WritableKeyPath<HOSCRDTState, CRDTField<V>>, to newValue: V) {
        guard var snapshot = hos else {
            // Lazy seed path — only the .status keyPath can bootstrap
            // the snapshot (it's the only field with a known default).
            // Other mutations are dropped until a seed lands.
            if let statusValue = newValue as? String {
                seedIfEmpty(
                    status: statusValue,
                    driveMinutes: 0,
                    windowMinutes: 0,
                    cycleMinutes: 0,
                    statusSince: Date()
                )
            }
            return
        }
        clock.tick(actor)
        snapshot[keyPath: keyPath] = CRDTField(
            value: newValue,
            actor: actor,
            clock: clock,
            ts: Date()
        )
        hos = snapshot
    }

    /// Ingest a remote snapshot (from iOS or another peer via mesh).
    /// Performs a per-field merge and ticks the local clock to absorb
    /// the remote causal history.
    func ingest(_ remote: HOSCRDTState) {
        guard let local = hos else {
            hos = remote
            return
        }
        let merged = local.merged(with: remote)
        // Absorb remote clock into our own so subsequent local ticks
        // remain strictly causally after everything we've seen.
        clock.merge(merged.status.clock)
        hos = merged
    }

    // MARK: - Load state

    /// Seed a load CRDT slot. No-op if the slot already exists — use
    /// `mutateLoad(...)` for subsequent updates so the clock ticks
    /// monotonically.
    func seedLoadIfEmpty(
        loadId: String,
        lifecycle: String,
        assignedDriverId: String,
        estimatedArrivalAt: Date,
        podUploaded: Bool = false,
        notes: String = ""
    ) {
        guard loads[loadId] == nil else { return }
        clock.tick(actor)
        let seedClock = clock
        let seedActor = actor
        let now = Date()
        loads[loadId] = LoadCRDTState(
            loadId: loadId,
            lifecycle:          CRDTField(value: lifecycle,          actor: seedActor, clock: seedClock, ts: now),
            assignedDriverId:   CRDTField(value: assignedDriverId,   actor: seedActor, clock: seedClock, ts: now),
            estimatedArrivalAt: CRDTField(value: estimatedArrivalAt, actor: seedActor, clock: seedClock, ts: now),
            podUploaded:        CRDTField(value: podUploaded,        actor: seedActor, clock: seedClock, ts: now),
            notes:              CRDTField(value: notes,              actor: seedActor, clock: seedClock, ts: now)
        )
    }

    /// Mutate a single load field locally. Mirrors the HOS `mutate(...)`
    /// contract: ticks the clock once, stamps the new field, republishes
    /// the snapshot, and is a no-op if the slot hasn't been seeded yet
    /// (caller responsibility — the app always seeds when it takes a
    /// load accept path).
    func mutateLoad<V>(
        _ loadId: String,
        keyPath: WritableKeyPath<LoadCRDTState, CRDTField<V>>,
        to newValue: V
    ) {
        guard var snap = loads[loadId] else { return }
        clock.tick(actor)
        snap[keyPath: keyPath] = CRDTField(
            value: newValue,
            actor: actor,
            clock: clock,
            ts: Date()
        )
        loads[loadId] = snap
    }

    /// Ingest a remote load snapshot. Runs per-field merge against our
    /// local copy and absorbs the remote causal history into the
    /// combined vector clock.
    func ingestLoad(_ remote: LoadCRDTState) {
        if let local = loads[remote.loadId] {
            let merged = local.merged(with: remote)
            clock.merge(merged.lifecycle.clock)
            clock.merge(merged.assignedDriverId.clock)
            clock.merge(merged.estimatedArrivalAt.clock)
            clock.merge(merged.podUploaded.clock)
            clock.merge(merged.notes.clock)
            loads[remote.loadId] = merged
        } else {
            loads[remote.loadId] = remote
            clock.merge(remote.lifecycle.clock)
        }
    }

    /// Convenience — emit the whole load snapshot wire envelope suitable
    /// for WCSession / convoy relay. Uses ISO dates via the default
    /// JSONEncoder strategy (the iOS companion's decoder mirrors it).
    func exportLoad(_ loadId: String) -> Data? {
        guard let snap = loads[loadId] else { return nil }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try? enc.encode(snap)
    }

    /// Inverse of `exportLoad` — used by WatchConnectivity peers and
    /// ConvoyRelay envelopes on inbound. Ingests + returns `true` on
    /// successful decode + merge.
    @discardableResult
    func importLoad(_ data: Data) -> Bool {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let snap = try? dec.decode(LoadCRDTState.self, from: data) else {
            return false
        }
        ingestLoad(snap)
        return true
    }
}
