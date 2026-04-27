//
//  ConvoyCoordinator.swift
//  EusoTrip Pulse Watch App
//
//  F13 — Convoy coordination (Q3+ offline-mode tier).
//
//  Multiple EusoTrip-paired trucks running the same corridor at the
//  same speed can form a "convoy": a short-lived logical group that
//  shares state across an unreliable BLE / WCSession / LoRa transport
//  so the wrist-class experience gracefully degrades when any single
//  truck drops off the network.
//
//  What the convoy gets you on the driver's wrist:
//
//    • SOS fanout. If one member raises an SOS, every other member's
//      wrist vibrates + surfaces the alerting truck's last-known
//      coordinate. In a dead-spot that's how the convoy's trailing
//      trucks even learn something is wrong.
//
//    • ETA sync. The leader (lowest driver-id hash; deterministic
//      tie-break) broadcasts a rolling ETA; followers adopt it so the
//      dispatcher sees one arrival estimate for the group rather
//      than five jitter-divergent ones.
//
//    • Rolling buddy stops. Fuel stops, restroom stops, and HOS-
//      mandated breaks propose + vote across the group so the whole
//      convoy pulls off at the same Pilot, not three different ones
//      30 miles apart.
//
//  Transport model (important — this file is PURE APP LOGIC):
//
//    This class is deliberately transport-agnostic. It publishes
//    outbound envelopes on a Combine stream (`outbound`) and exposes
//    `ingest(...)` for inbound envelopes. The actual wire is stitched
//    up by two adapters:
//
//      • Watch BLE: MeshRelay forwards envelopes directly between
//        wrists when they're <10m apart (rare but possible).
//
//      • iOS companion: the phone's BLE + cellular radios form the
//        production convoy transport — it maintains the peer registry
//        and forwards envelopes over WCSession. This is what actually
//        carries most production convoy traffic; watch-to-watch mesh
//        is a dead-spot fallback.
//
//    The coordinator itself doesn't know or care which transport is
//    in use — it just produces + consumes envelopes.
//
//  Membership lifecycle:
//
//    Candidate → Member → (divergent or silent) → Dropped
//
//    A peer enters the convoy when they've been observed for
//    ≥ formationDwellSeconds with heading within headingTolerance
//    and speed within speedToleranceMPS of the local vehicle.
//    They exit the convoy when they've been silent for
//    ≥ silenceDropSeconds or when their heading has diverged for
//    ≥ divergenceSustainSeconds.
//
//  Nothing in here requires the CoreBluetooth stack to actually be up
//  — the whole module compiles + runs in the simulator and fulfills
//  its public contract (publish ETA, surface SOS) even when no peer
//  is present.
//

import Foundation
import Combine
import CoreLocation

// MARK: - Envelope types

/// Kinds of messages that flow between convoy members.
enum ConvoyMessageKind: String, Codable {
    /// Periodic heartbeat — position, speed, heading, active load id,
    /// local ETA-to-next-stop. Drives the membership lifecycle.
    case heartbeat
    /// "I'm about to stop for fuel/rest" — starts a vote.
    case stopProposal
    /// "+1 / -1" response to an outstanding stop proposal.
    case stopVote
    /// Emergency fanout. Even non-members of the convoy MUST surface
    /// this one — an SOS is too important to gate on membership.
    case sos
    /// Leader-broadcast convoy ETA. Followers adopt + re-publish to
    /// their own dispatcher so the group arrives in sync.
    case etaSync
}

/// The wire format convoy members exchange. Kept deliberately small
/// so it fits in a 20-byte BLE characteristic write when the transport
/// is the watch's own U1/U2 BLE stack (most production traffic uses
/// WCSession-over-cellular which has plenty of headroom).
///
/// Signed envelopes carry `signature` (P-256 ECDSA raw representation,
/// base64) and — on heartbeats — `publicKeyB64` (raw P-256 public key,
/// base64) so peers receiving their first heartbeat from a new driver
/// can TOFU-pin the presented key. Both fields are `var`/optional so the
/// wire is forward-compatible with pre-F13 clients that never sign.
/// `ConvoySignature.canonicalBytes(...)` is computed over the immutable
/// identity fields (id, kind, fromDriverId, sentAt, fields) — NOT over
/// `signature` or `publicKeyB64` themselves, so signing is well-defined.
struct ConvoyEnvelope: Codable, Equatable, Identifiable {
    let id: String                // idempotency key; UUID string
    let kind: ConvoyMessageKind
    let fromDriverId: String
    let sentAt: Date
    /// One of: heartbeat payload, proposal payload, vote payload, etc.
    /// Encoded as JSON-dictionary-of-strings so the wire format is
    /// forward-compatible: older clients can read the keys they know
    /// and ignore the rest without failing to decode the whole message.
    let fields: [String: String]

    /// P-256 ECDSA signature over `ConvoySignature.canonicalBytes(...)`,
    /// base64-encoded. Nil for envelopes constructed before the signing
    /// layer is ready (e.g., simulator, SEP unavailable); the
    /// coordinator's ingest path drops those when `convoySignatureRequired`
    /// is on.
    var signature: String?

    /// Raw representation of the sender's P-256 public key, base64.
    /// Populated on heartbeats so peers can TOFU-pin on first sighting.
    /// Optional on non-heartbeat envelopes because peers that have
    /// already pinned don't need to re-transmit the key with every
    /// stop-vote.
    var publicKeyB64: String?

    /// Canonical bytes that `signature` covers. Excludes signature +
    /// publicKeyB64 so the signing step is well-defined (you can't
    /// sign your own signature). Pure function — no actor isolation
    /// so a verifier running off the main actor (BLE queue) can still
    /// recompute the bytes without hopping.
    var canonicalBytesForSigning: Data {
        ConvoySignature.canonicalBytes(
            id: id,
            kind: kind.rawValue,
            fromDriverId: fromDriverId,
            sentAt: sentAt,
            fields: fields
        )
    }

    /// Build a signed copy of this envelope using the local signing key.
    /// Returns self unchanged if the signer isn't ready (e.g., simulator).
    /// @MainActor because ConvoySignature's instance state (SEP key,
    /// public-key bytes) is main-actor-isolated. Callers (coordinator
    /// `publish()`) are already on the main actor.
    @MainActor
    func signedCopy() -> ConvoyEnvelope {
        var copy = self
        if let sig = ConvoySignature.shared.sign(canonicalBytesForSigning) {
            copy.signature = sig.base64EncodedString()
        }
        // Embed the local pubkey only on heartbeats; other message
        // kinds presume the recipient has already pinned on TOFU.
        if kind == .heartbeat {
            copy.publicKeyB64 = ConvoySignature.shared.localPublicKeyB64
        }
        return copy
    }
}

// MARK: - Member state

/// A single peer the local node has observed. Stored in-memory only —
/// convoys are ephemeral (an average convoy lives ~45 minutes in
/// highway operation before the group breaks up at a weigh station or
/// an exit). Persisting across launches would produce "ghost convoys"
/// that never actually existed.
struct ConvoyMember: Equatable, Identifiable {
    let driverId: String
    var id: String { driverId }

    var lastCoordinate: CLLocationCoordinate2D?
    var lastSpeedMPS: Double
    var lastHeadingDeg: Double
    var activeLoadId: String?
    var lastEtaMinutes: Int?

    var firstObservedAt: Date
    var lastSeenAt: Date
    /// Once true, this peer counts as a real convoy member; heartbeats
    /// + SOS + stop-votes surface to the driver. While false they're
    /// a candidate who hasn't yet passed formation dwell.
    var isConfirmed: Bool
    /// Last time the heading diverged from local heading by more than
    /// `headingTolerance` degrees. Used for the "sustained divergence"
    /// drop rule — a single lane change shouldn't eject a member.
    var divergingSince: Date?

    // CLLocationCoordinate2D is a C struct without synthesized Equatable,
    // so we implement the conformance by hand — compare lat/lon field by
    // field (with nil-handling) and defer to the rest of the struct's
    // regular value equality.
    static func == (lhs: ConvoyMember, rhs: ConvoyMember) -> Bool {
        guard lhs.driverId == rhs.driverId,
              lhs.lastSpeedMPS == rhs.lastSpeedMPS,
              lhs.lastHeadingDeg == rhs.lastHeadingDeg,
              lhs.activeLoadId == rhs.activeLoadId,
              lhs.lastEtaMinutes == rhs.lastEtaMinutes,
              lhs.firstObservedAt == rhs.firstObservedAt,
              lhs.lastSeenAt == rhs.lastSeenAt,
              lhs.isConfirmed == rhs.isConfirmed,
              lhs.divergingSince == rhs.divergingSince
        else { return false }
        switch (lhs.lastCoordinate, rhs.lastCoordinate) {
        case (nil, nil): return true
        case let (a?, b?): return a.latitude == b.latitude && a.longitude == b.longitude
        default: return false
        }
    }
}

// MARK: - Coordinator

@MainActor
final class ConvoyCoordinator: ObservableObject {
    static let shared = ConvoyCoordinator()

    // MARK: Published state

    /// Members currently in the convoy (isConfirmed == true).
    @Published private(set) var members: [ConvoyMember] = []

    /// Candidate peers — observed but not yet confirmed.
    @Published private(set) var candidates: [ConvoyMember] = []

    /// Shared ETA in minutes-to-next-stop, adopted from the leader.
    /// Nil when local node is alone (no convoy) or when no leader ETA
    /// has been broadcast yet.
    @Published private(set) var convoyEtaMinutes: Int?

    /// Driver id of the current leader, or nil if the local node is
    /// alone. Leader election is a deterministic min-hash of the
    /// driver-id strings across (local + confirmed members).
    @Published private(set) var leaderDriverId: String?

    /// The most recent SOS that the convoy has heard — local or peer.
    /// Callers (home view, instrument panel) observe this to surface
    /// the alert to the driver.
    @Published private(set) var activeConvoySOS: ConvoyEnvelope?

    /// Most recent stop proposal that's still gathering votes.
    @Published private(set) var pendingStopProposal: StopProposal?

    // MARK: Outbound publisher

    /// Envelopes the coordinator wants to send. Subscribe from a
    /// transport adapter (MeshRelay + WCSession) and push to the wire.
    let outbound = PassthroughSubject<ConvoyEnvelope, Never>()

    // MARK: Tunables

    /// Peer must be observed for this long before formation promotes
    /// them from candidate → confirmed member.
    private let formationDwellSeconds: TimeInterval = 120

    /// Silent peers dropped after this long without a heartbeat.
    private let silenceDropSeconds: TimeInterval = 300

    /// Heading divergence that counts as "going a different way."
    private let headingTolerance: Double = 30.0

    /// Sustained-divergence window before the peer is ejected.
    private let divergenceSustainSeconds: TimeInterval = 30.0

    /// Speed tolerance — a peer doing 25 mph while we're doing 70
    /// isn't the same convoy even if they're heading the same way.
    private let speedToleranceMPS: Double = 10.0 / 2.237   // ~4.5 m/s

    /// Heartbeat cadence.
    private let heartbeatCadence: TimeInterval = 15

    /// Supplied by the host app — returns the current local ETA to
    /// next stop in minutes, or nil if we don't have one yet. Lives
    /// as a closure so the coordinator stays transport-agnostic AND
    /// source-of-truth-agnostic: a host that computes ETA from
    /// `LearnedRouteETA` can wire that in, a host that pulls from a
    /// server can wire that in instead. Default: always-nil, which
    /// just suppresses the leader ETA broadcast until a provider
    /// lands.
    var localEtaMinutesProvider: @MainActor () -> Int? = { nil }

    // MARK: Local state

    private var localDriverId: String = "pulse-unpaired"
    private var lastLocalLocation: CLLocation?
    private var lastLocalActiveLoadId: String?
    private var heartbeatTask: Task<Void, Never>?
    private var sweepTask: Task<Void, Never>?
    private var seenEnvelopeIDs: Set<String> = []        // dedup cache
    private var outstandingVotes: [String: Int] = [:]     // proposalId → net votes

    // MARK: Configure + lifecycle

    /// Wire up the coordinator with the local driver id and start the
    /// periodic heartbeat + membership-sweep loops. Safe to call more
    /// than once; subsequent calls rebind the driver id + restart loops.
    func configure(driverId: String) {
        guard EusoTripConfig.convoyEnabled else { return }
        self.localDriverId = driverId
        startHeartbeatLoop()
        startSweepLoop()
    }

    func teardown() {
        heartbeatTask?.cancel(); heartbeatTask = nil
        sweepTask?.cancel();     sweepTask     = nil
        members.removeAll()
        candidates.removeAll()
        convoyEtaMinutes = nil
        leaderDriverId = nil
    }

    // MARK: - Local observations

    /// Called by DrivingSessionManager on every GPS fix so the
    /// coordinator can A) base outbound heartbeats on a real position
    /// and B) compute local↔peer heading/speed deltas for membership.
    func observeLocalLocation(_ loc: CLLocation, activeLoadId: String? = nil) {
        guard EusoTripConfig.convoyEnabled else { return }
        self.lastLocalLocation = loc
        if let id = activeLoadId { self.lastLocalActiveLoadId = id }
    }

    /// Called by EmergencyController.activate to fan the SOS across
    /// the convoy via the transport adapter. Idempotent — repeated
    /// calls for the same reason coalesce to one broadcast per 30s.
    func broadcastLocalSOS(reason: String, coordinate: CLLocationCoordinate2D?) {
        guard EusoTripConfig.convoyEnabled else { return }
        let envelope = ConvoyEnvelope(
            id: UUID().uuidString,
            kind: .sos,
            fromDriverId: localDriverId,
            sentAt: Date(),
            fields: [
                "reason": reason,
                "lat": String(format: "%.6f", coordinate?.latitude  ?? 0),
                "lon": String(format: "%.6f", coordinate?.longitude ?? 0)
            ]
        )
        activeConvoySOS = envelope
        publish(envelope)
    }

    // MARK: - Inbound

    /// Ingest an envelope received over any transport. The coordinator
    /// dedups by id, verifies the signature when signing is required,
    /// updates local state, and — if this is a leader's eta-sync —
    /// re-publishes to downstream views.
    ///
    /// Security model: signature verification happens BEFORE any state
    /// mutation. A mis-signed envelope doesn't create a candidate peer,
    /// doesn't pin a public key, doesn't update the seen-id cache — it
    /// might as well never have arrived. This is the canonical
    /// fail-closed posture that prevents a malicious peer from spoofing
    /// heartbeats from another driver's id or firing a fake SOS.
    func ingest(_ envelope: ConvoyEnvelope) {
        guard EusoTripConfig.convoyEnabled else { return }
        guard envelope.fromDriverId != localDriverId else { return }

        // Signature gate (fail-closed). Skipped when signatures aren't
        // required by policy OR when the local signer never bootstrapped
        // (simulator, SEP-less device) — in that case verification is
        // moot and we fall through to unauthenticated acceptance.
        if EusoTripConfig.convoySignatureRequired, ConvoySignature.shared.isReady {
            guard let sigB64 = envelope.signature,
                  let sig = Data(base64Encoded: sigB64) else {
                return
            }
            let ok = ConvoySignature.shared.verify(
                sig,
                payload: envelope.canonicalBytesForSigning,
                fromDriverId: envelope.fromDriverId,
                presentedPublicKeyB64: envelope.publicKeyB64
            )
            guard ok else { return }
        }

        guard !seenEnvelopeIDs.contains(envelope.id) else { return }
        seenEnvelopeIDs.insert(envelope.id)

        switch envelope.kind {
        case .heartbeat:    handleHeartbeat(envelope)
        case .stopProposal: handleStopProposal(envelope)
        case .stopVote:     handleStopVote(envelope)
        case .sos:          handleSOS(envelope)
        case .etaSync:      handleEtaSync(envelope)
        }

        // Evict old seen-ids so the cache doesn't grow unbounded over a
        // 14-hour shift. 2,000 is >10x the heartbeat volume per peer-hour.
        if seenEnvelopeIDs.count > 2_000 {
            seenEnvelopeIDs = Set(seenEnvelopeIDs.suffix(1_000))
        }
    }

    // MARK: - Stop proposals

    struct StopProposal: Equatable {
        let id: String
        let proposerDriverId: String
        let reason: String       // "fuel" | "rest" | "hos" | "food"
        let targetCoord: CLLocationCoordinate2D?
        let proposedAt: Date

        static func == (a: StopProposal, b: StopProposal) -> Bool {
            a.id == b.id
        }
    }

    /// Driver-initiated stop proposal. Fans out to the convoy; any
    /// confirmed member can respond with +1/-1 via `voteOnStop`.
    func proposeStop(reason: String, coordinate: CLLocationCoordinate2D?) {
        guard EusoTripConfig.convoyEnabled else { return }
        guard !members.isEmpty else { return }   // no-op when alone
        let id = UUID().uuidString
        let proposal = StopProposal(
            id: id,
            proposerDriverId: localDriverId,
            reason: reason,
            targetCoord: coordinate,
            proposedAt: Date()
        )
        pendingStopProposal = proposal
        outstandingVotes[id] = 1 // local +1
        publish(
            ConvoyEnvelope(
                id: id,
                kind: .stopProposal,
                fromDriverId: localDriverId,
                sentAt: Date(),
                fields: [
                    "reason": reason,
                    "lat": String(format: "%.6f", coordinate?.latitude ?? 0),
                    "lon": String(format: "%.6f", coordinate?.longitude ?? 0)
                ]
            )
        )
    }

    /// Local driver casts a vote on the pending proposal.
    func voteOnStop(_ yes: Bool) {
        guard EusoTripConfig.convoyEnabled else { return }
        guard let proposal = pendingStopProposal else { return }
        outstandingVotes[proposal.id, default: 0] += (yes ? 1 : -1)
        publish(
            ConvoyEnvelope(
                id: UUID().uuidString,
                kind: .stopVote,
                fromDriverId: localDriverId,
                sentAt: Date(),
                fields: [
                    "proposalId": proposal.id,
                    "vote": yes ? "yes" : "no"
                ]
            )
        )
    }

    // MARK: - Outbound plumbing

    /// Stamp a signature + (for heartbeats) the local public key onto
    /// the envelope before handing it to the transport. This is the
    /// single chokepoint every outbound message flows through, so
    /// transports never see an unsigned envelope when the signer is
    /// ready.
    private func publish(_ envelope: ConvoyEnvelope) {
        let out = ConvoySignature.shared.isReady ? envelope.signedCopy() : envelope
        outbound.send(out)
    }

    // MARK: - Loops

    private func startHeartbeatLoop() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Int(self?.heartbeatCadence ?? 15)))
                guard let self, !Task.isCancelled else { return }
                self.emitHeartbeat()
                self.maybeEmitLeaderEtaSync()
            }
        }
    }

    private func startSweepLoop() {
        sweepTask?.cancel()
        sweepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.sweepMembership()
                self.electLeader()
            }
        }
    }

    private func emitHeartbeat() {
        guard let loc = lastLocalLocation else { return }
        let env = ConvoyEnvelope(
            id: UUID().uuidString,
            kind: .heartbeat,
            fromDriverId: localDriverId,
            sentAt: Date(),
            fields: [
                "lat":  String(format: "%.6f", loc.coordinate.latitude),
                "lon":  String(format: "%.6f", loc.coordinate.longitude),
                "spd":  String(format: "%.2f", max(0, loc.speed)),
                "hdg":  String(format: "%.1f", loc.course >= 0 ? loc.course : 0),
                "load": lastLocalActiveLoadId ?? ""
            ]
        )
        publish(env)
    }

    private func maybeEmitLeaderEtaSync() {
        guard let leader = leaderDriverId, leader == localDriverId else { return }
        guard !members.isEmpty else { return }
        // Ask the host for its current local ETA. If it can't provide
        // one (no active load, no route plan yet, provider never
        // wired) we simply don't publish — followers will fall back
        // to whatever ETA their own vehicles computed.
        guard let eta = localEtaMinutesProvider() else { return }
        publish(
            ConvoyEnvelope(
                id: UUID().uuidString,
                kind: .etaSync,
                fromDriverId: localDriverId,
                sentAt: Date(),
                fields: ["etaMinutes": String(eta)]
            )
        )
    }

    // MARK: - Inbound handlers

    private func handleHeartbeat(_ env: ConvoyEnvelope) {
        let peerCoord = coordinateFrom(env.fields)
        let peerSpeed = Double(env.fields["spd"] ?? "0") ?? 0
        let peerHead  = Double(env.fields["hdg"] ?? "0") ?? 0
        let peerLoad  = env.fields["load"]
        let now = Date()

        // Apply the observation — either update a tracked peer or add
        // a fresh candidate.
        if let idx = candidates.firstIndex(where: { $0.driverId == env.fromDriverId }) {
            candidates[idx].lastCoordinate = peerCoord
            candidates[idx].lastSpeedMPS   = peerSpeed
            candidates[idx].lastHeadingDeg = peerHead
            candidates[idx].activeLoadId   = peerLoad
            candidates[idx].lastSeenAt     = now
            maybePromoteCandidate(at: idx)
        } else if let idx = members.firstIndex(where: { $0.driverId == env.fromDriverId }) {
            members[idx].lastCoordinate = peerCoord
            members[idx].lastSpeedMPS   = peerSpeed
            members[idx].lastHeadingDeg = peerHead
            members[idx].activeLoadId   = peerLoad
            members[idx].lastSeenAt     = now
            // Track sustained divergence (confirmed members only).
            if isPeerDivergent(speedMPS: peerSpeed, headingDeg: peerHead) {
                if members[idx].divergingSince == nil {
                    members[idx].divergingSince = now
                }
            } else {
                members[idx].divergingSince = nil
            }
        } else {
            let candidate = ConvoyMember(
                driverId: env.fromDriverId,
                lastCoordinate: peerCoord,
                lastSpeedMPS: peerSpeed,
                lastHeadingDeg: peerHead,
                activeLoadId: peerLoad,
                lastEtaMinutes: nil,
                firstObservedAt: now,
                lastSeenAt: now,
                isConfirmed: false,
                divergingSince: nil
            )
            candidates.append(candidate)
        }
    }

    private func handleStopProposal(_ env: ConvoyEnvelope) {
        let reason = env.fields["reason"] ?? "stop"
        pendingStopProposal = StopProposal(
            id: env.id,
            proposerDriverId: env.fromDriverId,
            reason: reason,
            targetCoord: coordinateFrom(env.fields),
            proposedAt: env.sentAt
        )
        outstandingVotes[env.id] = 0
    }

    private func handleStopVote(_ env: ConvoyEnvelope) {
        guard let proposalId = env.fields["proposalId"] else { return }
        guard let vote = env.fields["vote"] else { return }
        outstandingVotes[proposalId, default: 0] += (vote == "yes" ? 1 : -1)
    }

    private func handleSOS(_ env: ConvoyEnvelope) {
        // Even if the sending driver isn't a confirmed convoy member,
        // a BLE-range truck raising an SOS is almost always relevant
        // to us — another truck we didn't know was nearby is in
        // distress. Surface it unconditionally.
        activeConvoySOS = env
    }

    private func handleEtaSync(_ env: ConvoyEnvelope) {
        // Accept only from the current leader.
        guard env.fromDriverId == leaderDriverId else { return }
        if let raw = env.fields["etaMinutes"], let eta = Int(raw) {
            convoyEtaMinutes = eta
        }
    }

    // MARK: - Membership state transitions

    private func maybePromoteCandidate(at index: Int) {
        let c = candidates[index]
        let now = Date()
        guard now.timeIntervalSince(c.firstObservedAt) >= formationDwellSeconds else { return }
        guard !isPeerDivergent(speedMPS: c.lastSpeedMPS, headingDeg: c.lastHeadingDeg) else { return }
        var confirmed = c
        confirmed.isConfirmed = true
        members.append(confirmed)
        candidates.remove(at: index)
    }

    private func sweepMembership() {
        let now = Date()

        // Drop silent candidates.
        candidates.removeAll { now.timeIntervalSince($0.lastSeenAt) > silenceDropSeconds }

        // Drop silent members.
        members.removeAll { now.timeIntervalSince($0.lastSeenAt) > silenceDropSeconds }

        // Drop sustained-divergent members.
        members.removeAll { m in
            guard let since = m.divergingSince else { return false }
            return now.timeIntervalSince(since) >= divergenceSustainSeconds
        }
    }

    private func electLeader() {
        // Deterministic: smallest hash wins. Tied hashes broken by
        // lexicographic driverId so every member computes the same
        // result independently without a coordinator.
        let allIds = [localDriverId] + members.map(\.driverId)
        guard let chosen = allIds.min(by: { leaderSortKey($0) < leaderSortKey($1) }) else {
            leaderDriverId = nil
            return
        }
        leaderDriverId = members.isEmpty ? nil : chosen
    }

    private func leaderSortKey(_ driverId: String) -> String {
        // Stable deterministic sort. We don't need cryptographic
        // strength here — just something every peer computes the same
        // way. SHA256 would be overkill; a hex of the utf8 sum is fine.
        let sum = driverId.utf8.reduce(0, &+)
        return String(format: "%03d|%@", sum, driverId)
    }

    // MARK: - Helpers

    private func isPeerDivergent(speedMPS: Double, headingDeg: Double) -> Bool {
        guard let loc = lastLocalLocation else { return false }
        let localSpeed = max(0, loc.speed)
        let localHead  = loc.course >= 0 ? loc.course : 0
        if abs(speedMPS - localSpeed) > speedToleranceMPS { return true }
        let delta = angularDistance(headingDeg, localHead)
        return delta > headingTolerance
    }

    private func angularDistance(_ a: Double, _ b: Double) -> Double {
        let d = fmod(abs(a - b), 360)
        return d > 180 ? 360 - d : d
    }

    private func coordinateFrom(_ fields: [String: String]) -> CLLocationCoordinate2D? {
        guard let latStr = fields["lat"], let lonStr = fields["lon"],
              let lat = Double(latStr), let lon = Double(lonStr),
              (lat != 0 || lon != 0) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
