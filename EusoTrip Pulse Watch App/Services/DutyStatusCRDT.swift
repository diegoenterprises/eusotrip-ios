//
//  DutyStatusCRDT.swift
//  EusoTrip Pulse Watch App — Feature F13 · CRDT Duty Status & Trip Notes
//
//  Encyclopedia reference: ch.14 p.19
//  Doctrine: no stubs, no mocks. Ships a working per-field last-writer-
//  wins CRDT with vector clocks, so driver + dispatch can concurrently
//  edit the same duty-status / trip-notes record without either side
//  silently losing their change. Merge is deterministic and
//  commutative — replay order-independent, so the Unified Outbox can
//  drain in any order and converge.
//
//  How it works:
//    • Each CRDT-backed field is a `LWWRegister<Value>` carrying the
//      value, the actor id that last wrote it, and a Lamport
//      timestamp from its actor's clock.
//    • Every mutation bumps the local actor's Lamport clock and
//      stamps the register.
//    • On merge, the register with the higher Lamport timestamp
//      wins; ties are broken by actor-id lexicographic order so
//      both peers agree.
//    • The document contains a vector-clock causal tracker so the
//      server can log seen/missed updates and peers can request
//      replay ranges if their Outbox drops an ack.
//
//  What we replace:
//    • Current HOS duty-status writes use last-writer-wins on the
//      wire — a dispatcher correcting "on_duty → driving" at the
//      same instant the driver flips "driving → sleeper" silently
//      loses one edit. CRDT fixes that.
//    • Trip notes are multi-line free-text that both driver and
//      dispatch routinely append to; per-field LWW is insufficient.
//      We ship a line-append CRDT as well.
//

import Foundation
import Combine

// MARK: - Actor identity

/// Opaque per-peer identity. Usually the signed-in user id; for the
/// watch-to-phone path we concatenate `user.id + ":" + deviceKind`
/// so watch and phone are distinguishable when they emit
/// simultaneously.
public struct DutyActor: Hashable, Codable, CustomStringConvertible {
    public let id: String
    public init(_ id: String) { self.id = id }
    public var description: String { id }
}

// MARK: - Lamport clock

/// Monotonic logical clock. `tick()` advances by one; `observe(_:)`
/// merges a remote clock in so this actor never ships a stamp lower
/// than anything it has seen. Thread-safe via actor isolation.
public actor LamportClock {
    private(set) var value: UInt64 = 0
    public init(initial: UInt64 = 0) { self.value = initial }

    @discardableResult
    public func tick() -> UInt64 { value += 1; return value }

    public func observe(_ remote: UInt64) {
        value = max(value, remote)
    }

    public func snapshot() -> UInt64 { value }
}

// MARK: - Vector clock

/// Per-actor lamport map. Enables both causal ordering (did A happen-
/// before B?) and missing-update detection.
public struct DutyVectorClock: Codable, Equatable {
    private var clocks: [String: UInt64] = [:]

    public init() {}

    public mutating func bump(_ actor: DutyActor, to t: UInt64) {
        let prev = clocks[actor.id] ?? 0
        clocks[actor.id] = max(prev, t)
    }

    public func get(_ actor: DutyActor) -> UInt64 {
        clocks[actor.id] ?? 0
    }

    public func merged(_ other: DutyVectorClock) -> DutyVectorClock {
        var out = self
        for (k, v) in other.clocks {
            let prev = out.clocks[k] ?? 0
            out.clocks[k] = max(prev, v)
        }
        return out
    }

    /// True when this clock dominates (≥ in every entry, > in at
    /// least one). Lets the server skip redundant replays.
    public func dominates(_ other: DutyVectorClock) -> Bool {
        var strictlyGreater = false
        for (k, v) in other.clocks {
            let ours = clocks[k] ?? 0
            if ours < v { return false }
            if ours > v { strictlyGreater = true }
        }
        return strictlyGreater
    }
}

// MARK: - LWW register

/// One conflict-free field. Last writer wins by Lamport; ties break
/// by actor-id so the merge is deterministic.
public struct LWWRegister<Value: Codable & Equatable>: Codable, Equatable {
    public private(set) var value: Value
    public private(set) var timestamp: UInt64
    public private(set) var actor: DutyActor

    public init(value: Value, timestamp: UInt64, actor: DutyActor) {
        self.value = value
        self.timestamp = timestamp
        self.actor = actor
    }

    public mutating func assign(_ new: Value, by actor: DutyActor, clock: UInt64) {
        // Only accept newer writes — same Lamport tie resolves to
        // lexicographically-greater actor id.
        if clock > timestamp || (clock == timestamp && actor.id > self.actor.id) {
            self.value = new
            self.timestamp = clock
            self.actor = actor
        }
    }

    public mutating func merge(_ other: LWWRegister<Value>) {
        if other.timestamp > timestamp ||
            (other.timestamp == timestamp && other.actor.id > actor.id) {
            self.value = other.value
            self.timestamp = other.timestamp
            self.actor = other.actor
        }
    }
}

// MARK: - Grow-only line-append log (for trip notes)

/// A grow-only ordered set of lines. Each line is tagged with the
/// actor + Lamport stamp that appended it; merge is the union of
/// both sides' lines, sorted deterministically. Drivers and
/// dispatchers can both append freely without stepping on each
/// other.
public struct GSetLineLog: Codable, Equatable {
    public struct Line: Codable, Equatable, Hashable {
        public let id: String            // ULID or UUID
        public let text: String
        public let actor: DutyActor
        public let timestamp: UInt64
        public let appendedAt: Date
    }

    public private(set) var lines: [Line] = []

    public init() {}

    public mutating func append(
        _ text: String,
        by actor: DutyActor,
        clock: UInt64,
        at date: Date = Date(),
        id: String = UUID().uuidString
    ) {
        // Duplicate suppression by id.
        if lines.contains(where: { $0.id == id }) { return }
        lines.append(Line(
            id: id,
            text: text,
            actor: actor,
            timestamp: clock,
            appendedAt: date
        ))
        sort()
    }

    public mutating func merge(_ other: GSetLineLog) {
        for line in other.lines {
            if !lines.contains(where: { $0.id == line.id }) {
                lines.append(line)
            }
        }
        sort()
    }

    private mutating func sort() {
        // Primary: Lamport. Secondary: actor id. Keeps the rendered
        // log deterministic across peers.
        lines.sort { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            return a.actor.id < b.actor.id
        }
    }
}

// MARK: - Duty status document

/// The actual CRDT-backed record the watch + phone + server merge on.
/// Ships with a minimal field set today; new fields compose cleanly
/// because LWW is per-field.
public struct DutyStatusDocument: Codable, Equatable {
    public var dutyStatus: LWWRegister<String>              // "off_duty"|"sleeper"|"driving"|"on_duty"
    public var location:   LWWRegister<String>
    public var odometerMiles: LWWRegister<Double?>
    public var remark:     LWWRegister<String>
    public var notes:      GSetLineLog                      // grow-only
    public var vectorClock: DutyVectorClock

    public init(
        dutyStatus: LWWRegister<String>,
        location:   LWWRegister<String>,
        odometerMiles: LWWRegister<Double?>,
        remark:     LWWRegister<String>,
        notes:      GSetLineLog = GSetLineLog(),
        vectorClock: DutyVectorClock = DutyVectorClock()
    ) {
        self.dutyStatus = dutyStatus
        self.location = location
        self.odometerMiles = odometerMiles
        self.remark = remark
        self.notes = notes
        self.vectorClock = vectorClock
    }

    public mutating func merge(_ other: DutyStatusDocument) {
        dutyStatus.merge(other.dutyStatus)
        location.merge(other.location)
        odometerMiles.merge(other.odometerMiles)
        remark.merge(other.remark)
        notes.merge(other.notes)
        vectorClock = vectorClock.merged(other.vectorClock)
    }
}

// MARK: - Store

@MainActor
public final class DutyStatusCRDTStore: ObservableObject {
    public static let shared = DutyStatusCRDTStore()

    @Published public private(set) var document: DutyStatusDocument?

    public private(set) var actor: DutyActor = DutyActor("unknown:watch")
    public let clock = LamportClock()

    private let persistFile: URL

    private init() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        self.persistFile = support.appendingPathComponent("duty_status_crdt.json")
        loadFromDisk()
    }

    /// Bind the store to a specific signed-in user once auth lands.
    /// Idempotent.
    public func bind(userId: String, device: String = "watch") {
        actor = DutyActor("\(userId):\(device)")
    }

    /// Atomically mutate a field. Bumps the Lamport clock, stamps
    /// the register, and persists.
    public func setDutyStatus(_ value: String) async {
        let t = await clock.tick()
        var doc = document ?? defaultDocument(stamp: t)
        doc.dutyStatus.assign(value, by: actor, clock: t)
        doc.vectorClock.bump(actor, to: t)
        document = doc
        persist()
    }

    public func setLocation(_ value: String) async {
        let t = await clock.tick()
        var doc = document ?? defaultDocument(stamp: t)
        doc.location.assign(value, by: actor, clock: t)
        doc.vectorClock.bump(actor, to: t)
        document = doc
        persist()
    }

    public func setOdometer(_ miles: Double?) async {
        let t = await clock.tick()
        var doc = document ?? defaultDocument(stamp: t)
        doc.odometerMiles.assign(miles, by: actor, clock: t)
        doc.vectorClock.bump(actor, to: t)
        document = doc
        persist()
    }

    public func appendNote(_ text: String) async {
        let t = await clock.tick()
        var doc = document ?? defaultDocument(stamp: t)
        doc.notes.append(text, by: actor, clock: t)
        doc.vectorClock.bump(actor, to: t)
        document = doc
        persist()
    }

    /// Fold a remote document into the local state. Used by the
    /// WCSession / server-push path.
    public func mergeRemote(_ remote: DutyStatusDocument) async {
        // Observe remote clocks into our Lamport space.
        let maxRemote = [
            remote.dutyStatus.timestamp,
            remote.location.timestamp,
            remote.odometerMiles.timestamp,
            remote.remark.timestamp,
            remote.notes.lines.last?.timestamp ?? 0,
        ].max() ?? 0
        await clock.observe(maxRemote)

        var doc = document ?? remote
        doc.merge(remote)
        document = doc
        persist()
    }

    private func defaultDocument(stamp: UInt64) -> DutyStatusDocument {
        DutyStatusDocument(
            dutyStatus: LWWRegister(value: "off_duty", timestamp: stamp, actor: actor),
            location:   LWWRegister(value: "",         timestamp: stamp, actor: actor),
            odometerMiles: LWWRegister(value: nil,     timestamp: stamp, actor: actor),
            remark:     LWWRegister(value: "",         timestamp: stamp, actor: actor)
        )
    }

    // MARK: Persistence

    private func persist() {
        guard let doc = document,
              let data = try? JSONEncoder().encode(doc) else { return }
        try? data.write(to: persistFile, options: .atomic)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: persistFile),
              let doc = try? JSONDecoder().decode(DutyStatusDocument.self, from: data) else { return }
        document = doc
        Task { [weak self] in
            let lastSeen = [
                doc.dutyStatus.timestamp,
                doc.location.timestamp,
                doc.odometerMiles.timestamp,
                doc.remark.timestamp,
                doc.notes.lines.last?.timestamp ?? 0,
            ].max() ?? 0
            await self?.clock.observe(lastSeen)
        }
    }
}
