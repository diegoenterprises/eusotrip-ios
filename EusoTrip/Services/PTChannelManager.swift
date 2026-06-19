//
//  PTChannelManager.swift
//  EusoTrip
//
//  Chain-group walkie-talkie — the founder's flagship. A bespoke wrapper
//  around Apple's PushToTalk framework that lets every truck/driver on a
//  load's chain-group hold the wrist (or phone) and broadcast voice to
//  everyone else on that haul, the way a CB radio binds a convoy on I-35.
//
//  ─────────────────────────────────────────────────────────────────────
//  WHY THIS IS WRITTEN TO DEGRADE GRACEFULLY
//
//  Apple's PushToTalk framework requires the RESTRICTED entitlement
//  `com.apple.developer.pushtotalk`, which Apple grants by application
//  only. We have NOT been granted it yet, and adding it to a signed
//  build breaks codesigning the same way the unapproved PLA entitlement
//  did. So this file deliberately ships WITHOUT that entitlement:
//
//    • `import PushToTalk` is fine — the framework is on every iOS 16+
//      device; importing it does not require the entitlement.
//    • `PTChannelManager.channelManager(delegate:restorationDelegate:)`
//      THROWS at runtime when the entitlement is absent. We catch that,
//      flip `isAvailable = false`, and never crash. Every call site reads
//      `isAvailable` and hides the affordance, so the app behaves exactly
//      as it does today (PTT simply doesn't appear) until the founder
//      enables the capability — at which point this code lights up with
//      zero further changes.
//
//  THE CHANNEL MODEL
//
//  One PTT channel == one load's chain-group. The channel's
//  `PTChannelDescriptor.channelUUID` is derived deterministically from
//  the load's chain-group id (see `channelUUID(forChainGroup:)`) so every
//  member of the same haul, on every device, computes the IDENTICAL UUID
//  and therefore joins the IDENTICAL channel. When we join, Apple hands
//  us an ephemeral APNs push token scoped to that channel; we register it
//  with the backend via `notifications.registerPttToken` so the server's
//  `broadcastPttTransmission` can wake every other member with a
//  `pushType: 'pushtotalk'` payload when someone keys up.
//

import Foundation
import Combine
import PushToTalk
import AVFoundation
import UIKit
import CryptoKit

@MainActor
final class PTChannelManager: NSObject, ObservableObject {

    static let shared = PTChannelManager()

    // MARK: - Published state (read by every call site)

    /// `false` whenever the PushToTalk capability is not usable on this
    /// build/device — the entitlement is absent, the framework refused to
    /// vend a channel manager, or we're on a platform that doesn't ship
    /// PushToTalk. Call sites MUST gate the walkie-talkie affordance on
    /// this: when false they fall back to today's behavior (ESANG-only),
    /// never a broken button. This is the single honesty switch.
    @Published private(set) var isAvailable: Bool = false

    /// The chain-group id of the channel we're currently joined to, or
    /// nil when we're not in any channel. Drives the wrist UI's "you're
    /// on the convoy radio" affordance.
    @Published private(set) var joinedChainGroupId: String?

    /// True between `transmit()` and `stopTransmitting()` — i.e. while
    /// THIS device is the one keyed up and broadcasting. The UI uses this
    /// to paint the orb's transmit state.
    @Published private(set) var isTransmitting: Bool = false

    /// Human-readable reason PTT is unavailable, for diagnostics / an
    /// honest hint line. Never surfaced as a hard error to the driver.
    @Published private(set) var unavailableReason: String?

    // MARK: - Private

    /// Apple's channel manager. Optional because creating it THROWS when
    /// the entitlement isn't present — in that case it stays nil and
    /// `isAvailable` stays false. Everything below null-checks it.
    private var channelManager: PTChannelManager_Apple?

    /// The descriptor of the channel we asked to join, retained so we can
    /// leave cleanly and so the restoration delegate can re-join it.
    private var activeChannelUUID: UUID?

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Lazily create Apple's PTChannelManager. Safe to call repeatedly.
    /// On a build WITHOUT the entitlement this throws internally, we
    /// swallow it, and `isAvailable` stays false — no crash, ever.
    ///
    /// We intentionally do NOT call this at app launch from a hot path;
    /// it's invoked the first time a chain-group screen wants PTT, so the
    /// "framework refused" cost is paid once and cached.
    func bootstrapIfNeeded() async {
        guard channelManager == nil else { return }
        do {
            // The completion handler returns `(manager, error)`; the
            // framework reports a NON-nil error (and nil manager) when the
            // restricted `pushtotalk` entitlement is absent. We surface
            // that as a thrown error from the continuation and catch it —
            // that catch IS the whole graceful-degradation contract: no
            // entitlement ⇒ `isAvailable = false`, never a crash.
            let manager: PTChannelManager_Apple = try await withCheckedThrowingContinuation { cont in
                PTChannelManager_Apple.channelManager(
                    delegate: self,
                    restorationDelegate: self
                ) { manager, error in
                    if let manager {
                        cont.resume(returning: manager)
                    } else {
                        cont.resume(throwing: error ?? PTChannelError.unknown)
                    }
                }
            }
            self.channelManager = manager
            self.isAvailable = true
            self.unavailableReason = nil
        } catch {
            self.channelManager = nil
            self.isAvailable = false
            self.unavailableReason =
                "Push-to-Talk is not enabled on this build yet."
            #if DEBUG
            print("[PTChannelManager] channelManager creation failed " +
                  "(expected until the pushtotalk entitlement is granted): \(error)")
            #endif
        }
    }

    /// Local stand-in error so the continuation always has something to
    /// throw if the framework hands back neither a manager nor an error.
    private enum PTChannelError: Error { case unknown }

    // MARK: - Join / leave

    /// Join the walkie-talkie channel for a load's chain-group. Idempotent
    /// for the same chain-group; switching chain-groups leaves the old one
    /// first. No-op (and returns false) when PTT is unavailable so callers
    /// can decide to fall back to ESANG-only.
    ///
    /// - Parameters:
    ///   - chainGroupId: the load's chain-group id (stable across members)
    ///   - displayName:  what the system PTT banner shows (e.g. "LD-48291")
    /// - Returns: true once we're (or already were) joined.
    @discardableResult
    func join(chainGroupId: String, displayName: String) async -> Bool {
        await bootstrapIfNeeded()
        guard isAvailable, let manager = channelManager else { return false }

        let uuid = Self.channelUUID(forChainGroup: chainGroupId)

        // Already on this exact channel — nothing to do.
        if activeChannelUUID == uuid, joinedChainGroupId == chainGroupId {
            return true
        }

        // Switching haul: leave the previous channel cleanly first.
        if let previous = activeChannelUUID, previous != uuid {
            manager.leaveChannel(channelUUID: previous)
            activeChannelUUID = nil
            joinedChainGroupId = nil
        }

        let descriptor = PTChannelDescriptor(
            name: displayName,
            image: nil   // bespoke: no SF Symbol; system uses the app icon
        )

        // Apple's request is fire-and-forget (synchronous, void). The
        // real "we're joined" confirmation arrives on
        // `channelManager(_:didJoinChannel:reason:)`, and a failure on
        // `channelManager(_:failedToJoinChannel:error:)`. We optimistically
        // record the intent so the ephemeral-token delegate (which can
        // arrive first) knows which chain-group to register against.
        joinedChainGroupId = chainGroupId
        activeChannelUUID = uuid
        manager.requestJoinChannel(channelUUID: uuid, descriptor: descriptor)
        return true
    }

    /// Leave the current chain-group channel (e.g. when the load is
    /// delivered or the driver signs off the haul).
    func leave() async {
        guard let manager = channelManager, let uuid = activeChannelUUID else {
            joinedChainGroupId = nil
            activeChannelUUID = nil
            return
        }
        manager.leaveChannel(channelUUID: uuid)
        activeChannelUUID = nil
        joinedChainGroupId = nil
        isTransmitting = false
    }

    // MARK: - Transmit (key up / key down)

    /// Key up — begin broadcasting to everyone on the chain-group. Maps to
    /// the wrist long-press DOWN. No-op when PTT is unavailable or we're
    /// not joined (caller falls back to ESANG).
    func transmit() async {
        guard isAvailable, let manager = channelManager,
              let uuid = activeChannelUUID, !isTransmitting else { return }
        // Synchronous request; `didBeginTransmittingFrom` confirms and
        // `failedToBeginTransmittingInChannel` corrects. Optimistically
        // flip so the UI paints the keyed-up state immediately.
        isTransmitting = true
        manager.requestBeginTransmitting(channelUUID: uuid)
    }

    /// Key down — stop broadcasting. Maps to the wrist long-press RELEASE.
    /// Safe to call when not transmitting.
    func stopTransmitting() async {
        guard let manager = channelManager, let uuid = activeChannelUUID else {
            isTransmitting = false
            return
        }
        manager.stopTransmitting(channelUUID: uuid)
        isTransmitting = false
    }

    // MARK: - Channel UUID derivation
    //
    // The chain-group id is an opaque server string. Every member of the
    // haul must independently compute the SAME PTChannelDescriptor UUID
    // so they all land in the same channel. We hash the id into a
    // deterministic, RFC-4122-shaped UUID (a "name-based" UUID, v5-style)
    // under a fixed EusoTrip namespace. If the id ALREADY is a valid
    // UUID (which load chain-group ids may be), we use it verbatim.

    /// Fixed namespace so the derived UUIDs never collide with unrelated
    /// UUID spaces. This is the EusoTrip PTT chain-group namespace —
    /// a hard-coded, valid RFC-4122 UUID shared by every client.
    private static let chainGroupNamespace =
        UUID(uuidString: "E5A06A11-0000-4E75-9000-EE5070119901")!

    static func channelUUID(forChainGroup chainGroupId: String) -> UUID {
        if let direct = UUID(uuidString: chainGroupId) {
            return direct
        }
        return Self.deterministicUUID(
            namespace: chainGroupNamespace,
            name: chainGroupId
        )
    }

    /// Name-based deterministic UUID (RFC-4122 §4.3 shape, SHA-256 digest
    /// truncated to 128 bits, version/variant bits set). We don't need
    /// cryptographic agreement here — only that all members map the same
    /// string to the same UUID — so SHA-256 over (namespace || name) is
    /// more than sufficient and avoids importing CommonCrypto's MD5/SHA1.
    private static func deterministicUUID(namespace: UUID, name: String) -> UUID {
        var bytes = [UInt8]()
        bytes.append(contentsOf: tupleToArray(namespace.uuid))
        bytes.append(contentsOf: Array(name.utf8))

        let digest = sha256(bytes)
        var u = Array(digest.prefix(16))
        // Set version to 5 (name-based) and the RFC-4122 variant.
        u[6] = (u[6] & 0x0F) | 0x50
        u[8] = (u[8] & 0x3F) | 0x80
        return UUID(uuid: (
            u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7],
            u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]
        ))
    }

    private static func tupleToArray(_ t: uuid_t) -> [UInt8] {
        [t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
         t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15]
    }

    /// Minimal dependency-free SHA-256 (used only for stable UUID
    /// derivation, never for security). Pulls from CryptoKit which is
    /// always available on iOS 13+.
    private static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        SHA256Box.digest(bytes)
    }

    // MARK: - Server registration

    /// Register the ephemeral push token Apple vends on join with the
    /// backend, keyed to this chain-group. The server stores it in
    /// `push_tokens_ptt` and uses it from `broadcastPttTransmission` to
    /// wake every other member with a `pushType: 'pushtotalk'` payload.
    /// Fire-and-forget; a failure must never break the join.
    private func registerEphemeralToken(
        _ token: Data, chainGroupId: String
    ) async {
        struct Input: Encodable {
            let loadChainGroupId: String
            let ephemeralPushToken: String
        }
        struct Ack: Decodable { let success: Bool? }

        let hex = token.map { String(format: "%02x", $0) }.joined()
        let _: Ack? = try? await EusoTripAPI.shared.mutation(
            "notifications.registerPttToken",
            input: Input(loadChainGroupId: chainGroupId, ephemeralPushToken: hex)
        )
        #if DEBUG
        print("[PTChannelManager] registered ephemeral PTT token " +
              "for chain-group \(chainGroupId) · \(hex.prefix(8))…")
        #endif
    }
}

// MARK: - SHA-256 helper (CryptoKit-backed)

private enum SHA256Box {
    static func digest(_ bytes: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(bytes)))
    }
}

// MARK: - Apple PTChannelManager type alias
//
// Apple's framework type is literally named `PTChannelManager`, which
// would collide with OUR class of the same name. We alias Apple's type so
// our wrapper can keep the canonical EusoTrip name at every call site
// (`PTChannelManager.shared`) while still driving Apple's implementation.

typealias PTChannelManager_Apple = PushToTalk.PTChannelManager

// MARK: - PTChannelManagerDelegate
//
// Apple calls these on the main thread; the manager is @MainActor, so each
// hop is a plain Task. Every required protocol method is implemented to the
// EXACT framework signature (verified against the iOS SDK headers). When the
// `pushtotalk` entitlement is absent the channel manager is never created,
// so none of these are ever called — that's the graceful-degradation path.

extension PTChannelManager: PTChannelManagerDelegate {

    /// Apple vends the ephemeral APNs push token for the joined channel.
    /// THIS is the token the server needs in `push_tokens_ptt`.
    nonisolated func channelManager(
        _ channelManager: PushToTalk.PTChannelManager,
        receivedEphemeralPushToken pushToken: Data
    ) {
        Task { @MainActor [weak self] in
            guard let self, let chainGroupId = self.joinedChainGroupId else { return }
            await self.registerEphemeralToken(pushToken, chainGroupId: chainGroupId)
        }
    }

    /// We successfully joined. Mark the channel active.
    nonisolated func channelManager(
        _ channelManager: PushToTalk.PTChannelManager,
        didJoinChannel channelUUID: UUID,
        reason: PTChannelJoinReason
    ) {
        Task { @MainActor [weak self] in
            self?.activeChannelUUID = channelUUID
        }
    }

    /// We left (intentionally or by system). Clear local state.
    nonisolated func channelManager(
        _ channelManager: PushToTalk.PTChannelManager,
        didLeaveChannel channelUUID: UUID,
        reason: PTChannelLeaveReason
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.activeChannelUUID == channelUUID {
                self.activeChannelUUID = nil
                self.joinedChainGroupId = nil
                self.isTransmitting = false
            }
        }
    }

    /// This device keyed up (locally or via an accessory). Paint transmit.
    nonisolated func channelManager(
        _ channelManager: PushToTalk.PTChannelManager,
        channelUUID: UUID,
        didBeginTransmittingFrom source: PTChannelTransmitRequestSource
    ) {
        Task { @MainActor [weak self] in
            self?.isTransmitting = true
        }
    }

    nonisolated func channelManager(
        _ channelManager: PushToTalk.PTChannelManager,
        channelUUID: UUID,
        didEndTransmittingFrom source: PTChannelTransmitRequestSource
    ) {
        Task { @MainActor [weak self] in
            self?.isTransmitting = false
        }
    }

    /// REQUIRED. The system delivers a `pushType: 'pushtotalk'` payload
    /// from the server's `broadcastPttTransmission`. We answer with the
    /// active remote participant so the system opens the speaker for the
    /// person keying up. The payload carries the speaker's display name
    /// under "activeParticipant" (server contract); we fall back to the
    /// brand if it's absent so the banner is never blank.
    nonisolated func incomingPushResult(
        channelManager: PushToTalk.PTChannelManager,
        channelUUID: UUID,
        pushPayload: [String: Any]
    ) -> PTPushResult {
        let name = (pushPayload["activeParticipant"] as? String)
            ?? (pushPayload["speakerName"] as? String)
            ?? "EusoTrip Convoy"
        let participant = PTParticipant(name: name, image: nil)
        return .activeRemoteParticipant(participant)
    }

    /// The system activated the audio session for an incoming or outgoing
    /// transmission. Configure play-and-record + voice-chat so the
    /// walkie-talkie sounds like a radio, not a phone call.
    nonisolated func channelManager(
        _ channelManager: PushToTalk.PTChannelManager,
        didActivate audioSession: AVAudioSession
    ) {
        configureRadioSession(audioSession)
    }

    nonisolated func channelManager(
        _ channelManager: PushToTalk.PTChannelManager,
        didDeactivate audioSession: AVAudioSession
    ) {
        try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private nonisolated func configureRadioSession(_ audioSession: AVAudioSession) {
        try? audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .duckOthers]
        )
        try? audioSession.setActive(true)
    }
}

// MARK: - PTChannelRestorationDelegate
//
// After a relaunch the system can ask us to re-create the descriptor for
// a channel it's restoring. The system only restores channels it believes
// are live, so a brand-named descriptor is enough to satisfy the banner
// until the next join refreshes the friendlier load label.

extension PTChannelManager: PTChannelRestorationDelegate {
    nonisolated func channelDescriptor(
        restoredChannelUUID channelUUID: UUID
    ) -> PTChannelDescriptor {
        PTChannelDescriptor(name: "EusoTrip Convoy", image: nil)
    }
}
