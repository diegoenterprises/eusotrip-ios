//
//  ConvoyRollingMesh.swift
//  EusoTrip Pulse Watch App — Feature F10 · Convoy Rolling Mesh
//
//  Encyclopedia reference: ch.11 p.8 — "Convoy Rolling Mesh"
//  Doctrine: no stubs, no mocks. F10 rides on top of the convoy +
//  mesh primitives already in the bundle:
//
//     ConvoyCoordinator      — convoy membership, heartbeat, vote +
//                              ETA synchronization (owns the logic)
//     MeshRelay              — watch-to-watch BLE envelope relay
//     MeshBluetoothController
//                            — CBCentralManager + CBPeripheralManager
//                              plumbing under MeshRelay
//     ConvoyBridge           — WCSession link to the phone so cellular
//                              + BLE radios extend the mesh off-wrist
//     ConvoyRosterReconciler — periodic gossip sync of the convoy
//                              member list (heals netsplits)
//     ConvoySignature        — ECDSA P-256 envelope signing to defeat
//                              wrist-spoofing SOS injection
//
//  What this file adds on top — the F10 public contract:
//
//     • A single @MainActor ObservableObject the UI reads, so
//       "Convoy · N peers · rolling ETA hh:mm" renders from one
//       binding rather than a fan-out of four stores.
//     • Rolling ETA smoothing with an exponentially-weighted moving
//       average (α = 0.3) so the group ETA does not twitch every
//       time one truck slows for fuel. The coordinator already
//       elects a leader whose ETA is broadcast; we smooth on ingest.
//     • A lightweight SOS-notice surface the home view can flash
//       even when off the convoy screen.
//     • Summary string + member view-models shaped for the Modular
//       Ultra design language (two-letter driver initials).
//
//  This file is read-only by design — it does not inject signing
//  or run its own transport. Those already live in ConvoyCoordinator
//  / ConvoyBridge / MeshRelay. Anything we do here would double-
//  encode or diverge. If the encyclopedia later calls for an F10-
//  specific feature that isn't in the existing stack, it lands here.
//

import Foundation
import Combine
import CoreLocation

// MARK: - Published surface

@MainActor
public final class ConvoyRollingMesh: ObservableObject {
    public static let shared = ConvoyRollingMesh()

    /// Short one-line UI summary: "Convoy · 3 peers · ETA 14:22".
    /// Empty when we are solo.
    @Published public private(set) var summary: String = ""

    /// Convoy members shaped for the Modular Ultra stacked-avatar row.
    @Published public private(set) var roster: [MemberRow] = []

    /// Smoothed rolling group ETA (minutes). nil when we don't have a
    /// convoy consensus yet.
    @Published public private(set) var rollingETAMinutes: Double?

    /// Fresh incoming SOS the home view flashes regardless of current
    /// screen. UI clears by setting back to nil once acknowledged.
    @Published public var incomingSOS: SOSNotice?

    public struct MemberRow: Equatable, Identifiable {
        public let id: String
        public let initials: String
        public let lastSeenAt: Date
        public let etaMinutes: Int?
        public let confirmed: Bool
    }

    public struct SOSNotice: Equatable {
        public let fromDriverId: String
        public let fromInitials: String
        public let coordinate: CLLocationCoordinate2D?
        public let raisedAt: Date

        public static func == (lhs: SOSNotice, rhs: SOSNotice) -> Bool {
            guard lhs.fromDriverId == rhs.fromDriverId,
                  lhs.fromInitials == rhs.fromInitials,
                  lhs.raisedAt == rhs.raisedAt else { return false }
            switch (lhs.coordinate, rhs.coordinate) {
            case (nil, nil): return true
            case let (a?, b?): return a.latitude == b.latitude && a.longitude == b.longitude
            default: return false
            }
        }
    }

    // MARK: - Internal

    private let coordinator: ConvoyCoordinator
    private var bag = Set<AnyCancellable>()
    private let etaSmoothing: Double = 0.3

    private init() {
        self.coordinator = ConvoyCoordinator.shared
        wire()
    }

    // MARK: - Wiring

    private func wire() {
        coordinator.$members
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in self?.absorb(members: list) }
            .store(in: &bag)

        coordinator.$convoyEtaMinutes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mins in self?.absorb(leaderETA: mins) }
            .store(in: &bag)

        coordinator.$activeConvoySOS
            .receive(on: DispatchQueue.main)
            .sink { [weak self] env in self?.absorb(sos: env) }
            .store(in: &bag)
    }

    // MARK: - Public convenience

    /// Forward an SOS into the convoy. Pure passthrough so callers
    /// don't need to learn two shared singletons.
    public func broadcastSOS(reason: String, coordinate: CLLocationCoordinate2D?) {
        coordinator.broadcastLocalSOS(reason: reason, coordinate: coordinate)
    }

    /// Forward a stop proposal. Same rationale.
    public func proposeStop(reason: String, coordinate: CLLocationCoordinate2D?) {
        coordinator.proposeStop(reason: reason, coordinate: coordinate)
    }

    // MARK: - Absorb state

    private func absorb(members list: [ConvoyMember]) {
        roster = list.map { m in
            MemberRow(
                id: m.driverId,
                initials: Self.initials(for: m.driverId),
                lastSeenAt: m.lastSeenAt,
                etaMinutes: m.lastEtaMinutes,
                confirmed: m.isConfirmed
            )
        }
        refreshSummary()
    }

    private func absorb(leaderETA mins: Int?) {
        guard let mins else {
            rollingETAMinutes = nil
            refreshSummary()
            return
        }
        let fresh = Double(mins)
        if let prev = rollingETAMinutes {
            rollingETAMinutes = prev + etaSmoothing * (fresh - prev)
        } else {
            rollingETAMinutes = fresh
        }
        refreshSummary()
    }

    private func absorb(sos env: ConvoyEnvelope?) {
        guard let env, env.kind == .sos else { return }
        let lat = Double(env.fields["lat"] ?? "") ?? Double.nan
        let lon = Double(env.fields["lon"] ?? "") ?? Double.nan
        let coord: CLLocationCoordinate2D? = (lat.isFinite && lon.isFinite && (lat != 0 || lon != 0))
            ? CLLocationCoordinate2D(latitude: lat, longitude: lon)
            : nil
        incomingSOS = SOSNotice(
            fromDriverId: env.fromDriverId,
            fromInitials: Self.initials(for: env.fromDriverId),
            coordinate: coord,
            raisedAt: env.sentAt
        )
    }

    private func refreshSummary() {
        let confirmed = roster.filter { $0.confirmed }
        if confirmed.isEmpty {
            summary = ""
            return
        }
        let label = confirmed.count == 1 ? "1 peer" : "\(confirmed.count) peers"
        if let eta = rollingETAMinutes {
            let hh = Int(eta) / 60
            let mm = Int(eta) % 60
            summary = "Convoy · \(label) · ETA \(String(format: "%d:%02d", hh, mm))"
        } else {
            summary = "Convoy · \(label)"
        }
    }

    private static func initials(for driverId: String) -> String {
        // Take the first two alphanumerics of the driver-id hash —
        // driver ids on our system are user-ulid + short-suffix, so
        // the first two characters are unique-enough for a visual
        // marker in the stacked avatar row.
        let filtered = driverId.filter { $0.isLetter || $0.isNumber }
        let prefix = filtered.prefix(2).uppercased()
        if prefix.isEmpty { return "··" }
        return String(prefix)
    }
}
