//
//  MeshRelay.swift
//  EusoTrip Pulse Watch App
//
//  Q3 2026 offline-mode tier — peer-to-peer mesh relay.
//
//  When the driver is in a long dead-spot and another EusoTrip-paired
//  truck is nearby, the wrist can forward queued high-priority items
//  (SOS, HOS log events) through the peer's cellular link. This uses
//  CoreBluetooth for the local discovery layer; a future iteration
//  pairs with a 915 MHz Meshtastic-style LoRa daughter board on the
//  truck for 5-mile range.
//
//  State machine:
//     advertise → discover → handshake → relay → ack
//
//  Every relayed item carries:
//    • Signed origin payload (Ed25519, keys live in the Secure Enclave).
//    • TTL (hop count, max 3).
//    • Idempotency key — matched against the origin outbox on ack so a
//      successful relay dequeues the message at the origin too.
//
//  This file is the scaffold: state machine, advertisement service UUID,
//  and the public `attemptRelay(_:)` entry point. The CoreBluetooth
//  central/peripheral plumbing lands in a subsequent PR; today the mesh
//  is a no-op if `EusoTripConfig.meshRelayEnabled == false`, and a
//  loopback when enabled without a peer present.
//

import Foundation
import Combine
#if canImport(CoreBluetooth) && !os(watchOS)
import CoreBluetooth
#endif

enum MeshRelayState: Equatable {
    case idle
    case advertising
    case discovering
    case handshaking(peerId: String)
    case relaying(peerId: String, count: Int)
    case error(String)
}

struct MeshEnvelope: Codable, Equatable {
    let idempotencyKey: String
    let originDriverId: String
    let ttl: Int
    let createdAt: Date
    let lane: OutboxLane
    let payloadKind: String // e.g. "sos" | "hos.event" | "message"
    let payload: Data       // opaque; decoded server-side

    /// New envelope with ttl decremented by 1.
    func relayed() -> MeshEnvelope? {
        guard ttl > 0 else { return nil }
        return MeshEnvelope(
            idempotencyKey: idempotencyKey,
            originDriverId: originDriverId,
            ttl: ttl - 1,
            createdAt: createdAt,
            lane: lane,
            payloadKind: payloadKind,
            payload: payload
        )
    }
}

@MainActor
final class MeshRelay: ObservableObject {
    static let shared = MeshRelay()

    @Published private(set) var state: MeshRelayState = .idle
    @Published private(set) var peersInRange: [String] = []
    @Published private(set) var bytesRelayedSession: Int = 0

    /// Most recent BLE state string reported by the controller
    /// ("central:poweredOn", "peripheral:unsupported", etc). Surfaced
    /// in the debug overlay so QA can diagnose a wrist that isn't
    /// seeing peers without a CoreBluetooth packet capture.
    @Published private(set) var lastBluetoothState: String = "idle"

    /// Advertising service UUID — a fixed 128-bit identifier so two
    /// EusoTrip wrists recognize each other instantly without a paired
    /// account.
    static let serviceUUID = "9F8E9D00-E050-4C0C-9E0F-EEB4D0A7B01E"
    static let maxTTL = 3

    // MARK: - Bluetooth controller

    #if canImport(CoreBluetooth) && !os(watchOS)
    /// CoreBluetooth plumbing. Lazy so that on a device without BLE
    /// (extremely rare for Apple Watch but possible for unit tests)
    /// the instantiation is deferred until `begin()` actually needs it.
    private lazy var bluetooth: MeshBluetoothController = {
        let c = MeshBluetoothController()
        // The three callbacks run on the BLE queue. Each hops to the
        // main actor before touching any @MainActor state.
        c.onInboundEnvelope = { data in
            Task { @MainActor in
                MeshRelay.shared.handleInboundPayload(data)
            }
        }
        c.onPeersChanged = { ids in
            Task { @MainActor in
                MeshRelay.shared.handlePeersChanged(ids)
            }
        }
        c.onStateChanged = { stateString in
            Task { @MainActor in
                MeshRelay.shared.handleBluetoothStateChanged(stateString)
            }
        }
        return c
    }()
    #endif

    /// Enable the mesh. Begins advertising the EusoTrip service UUID
    /// and scanning for peers. Safe to call multiple times.
    func begin() {
        guard EusoTripConfig.meshRelayEnabled else { return }
        guard state == .idle else { return }
        state = .advertising
        #if canImport(CoreBluetooth) && !os(watchOS)
        bluetooth.start()
        #endif
    }

    func end() {
        #if canImport(CoreBluetooth) && !os(watchOS)
        bluetooth.stop()
        #endif
        state = .idle
        peersInRange.removeAll()
    }

    /// Attempt to relay a high-priority outbox item through any peer in
    /// range. Returns true if at least one peer accepted the envelope;
    /// false if no peer is reachable (caller keeps the item in the
    /// local outbox).
    ///
    /// "Accepted" here means the envelope was handed to the BLE layer
    /// for a GATT write to every connected peer. The actual write-
    /// response ack is handled per-peer inside the controller and
    /// doesn't gate this return value — the coordinator's idempotency
    /// layer de-duplicates if multiple peers + the origin all deliver
    /// the same envelope.
    func attemptRelay(_ envelope: MeshEnvelope) async -> Bool {
        guard EusoTripConfig.meshRelayEnabled else { return false }
        guard envelope.ttl > 0 else { return false }
        guard !peersInRange.isEmpty else { return false }
        guard let peer = peersInRange.first else { return false }
        state = .relaying(peerId: peer, count: 1)
        bytesRelayedSession += envelope.payload.count
        #if canImport(CoreBluetooth) && !os(watchOS)
        if let data = try? JSONEncoder().encode(envelope) {
            bluetooth.broadcast(data)
        }
        #endif
        state = .idle
        return true
    }

    // MARK: - Main-actor controller callbacks

    /// Called (hopped to main actor) when the controller delivers bytes
    /// written by a peer into our inbound characteristic. We decode as
    /// MeshEnvelope first (that's the generic wrapper BLE carries) and
    /// route by `payloadKind`: convoy.* payloads get unwrapped back
    /// into ConvoyEnvelope and handed to the coordinator; other
    /// payload kinds will grow routes in subsequent drops.
    fileprivate func handleInboundPayload(_ data: Data) {
        guard EusoTripConfig.meshRelayEnabled else { return }
        guard let mesh = try? JSONDecoder().decode(MeshEnvelope.self, from: data) else { return }
        bytesRelayedSession += mesh.payload.count
        if mesh.payloadKind.hasPrefix("convoy.") {
            deliverInboundConvoy(payload: mesh.payload)
        }
        // Future: SOS/HOS lanes get routed into OfflineQueue here so
        // the receiving wrist's phone picks them up on its next flush.
    }

    fileprivate func handlePeersChanged(_ ids: [String]) {
        peersInRange = ids
    }

    fileprivate func handleBluetoothStateChanged(_ stateString: String) {
        lastBluetoothState = stateString
    }

    /// Forward a convoy coordinator envelope over the mesh. Same
    /// semantics as attemptRelay — returns true on accept, false if
    /// no peer is reachable. Serializes the ConvoyEnvelope into the
    /// generic MeshEnvelope's opaque payload.
    @discardableResult
    func forwardConvoyEnvelope(_ env: ConvoyEnvelope, originDriverId: String) async -> Bool {
        guard EusoTripConfig.meshRelayEnabled else { return false }
        guard let payload = try? JSONEncoder().encode(env) else { return false }
        let wrapper = MeshEnvelope(
            idempotencyKey: env.id,
            originDriverId: originDriverId,
            ttl: Self.maxTTL,
            createdAt: env.sentAt,
            lane: env.kind == .sos ? .sos : .message,
            payloadKind: "convoy.\(env.kind.rawValue)",
            payload: payload
        )
        return await attemptRelay(wrapper)
    }

    /// Inbound hook called by the CoreBluetooth delegate (or by the
    /// iOS companion via WCSession) when a peer has delivered a
    /// convoy envelope addressed to this node. Decodes + routes into
    /// the coordinator's ingest path. Drops silently on bad payloads.
    func deliverInboundConvoy(payload: Data) {
        guard EusoTripConfig.meshRelayEnabled else { return }
        guard let env = try? JSONDecoder().decode(ConvoyEnvelope.self, from: payload) else { return }
        ConvoyCoordinator.shared.ingest(env)
    }

    /// Consume any SOS/HOS items from the outbox that are ready (past
    /// their backoff) and attempt to push them through a peer instead
    /// of waiting for the origin's cellular to come back. Called on a
    /// 15-second loop while in a known dead-spot region.
    func drainHighPriority(driverId: String) async {
        guard EusoTripConfig.meshRelayEnabled else { return }
        let outbox = OfflineQueue.shared
        for entry in outbox.entries(in: .sos) + outbox.entries(in: .hos) where entry.isReady() {
            let env = MeshEnvelope(
                idempotencyKey: entry.id,
                originDriverId: driverId,
                ttl: Self.maxTTL,
                createdAt: entry.enqueuedAt,
                lane: entry.lane,
                payloadKind: payloadKind(for: entry.action),
                payload: Data()
            )
            _ = await attemptRelay(env)
        }
    }

    private func payloadKind(for action: QueuedAction) -> String {
        switch action {
        case .sos:        return "sos"
        case .hosEvent:   return "hos.event"
        case .voice:      return "voice"
        case .acceptLoad: return "load.accept"
        case .arrived:    return "load.arrived"
        case .message:    return "message"
        }
    }
}
