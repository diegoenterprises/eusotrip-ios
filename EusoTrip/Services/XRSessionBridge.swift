//
//  XRSessionBridge.swift
//  Audio-only XR pre-haul checklist bridge — IO 2026 P0-16.
//
//  Drives the driver-side XR pre-haul session:
//
//    1. Phone fetches the canonical checklist via
//       `xrChecklist.getChecklist({loadId})` — server selects items
//       per the load's vertical + trailerCode + cross-border flag.
//    2. Bridge iterates items in order, reading each `spokenPrompt`
//       aloud via `ESangTTSPlayer.shared.speak(_:)`. Audio routes
//       through whichever output is active — Bluetooth-paired
//       Warby Parker frames, AirPods, CarPlay speaker.
//    3. Driver says the matching `confirmPhrases` ("placard verified",
//       "ERG confirmed", "tie-downs count ok"…). The bridge submits
//       the transcript to `xrChecklist.confirmItem` which validates
//       the phrase, writes the Ed25519-signed audit chain row, and
//       — when the item maps to an FSM overlay — writes the overlay
//       row too. Driver hears the next item.
//    4. Resume-after-disconnect: if the headset drops, the bridge
//       re-queries server state on re-pair and picks up where the
//       driver left off.
//
//  Platform-agnostic by design (per the founder's directive: XR
//  ships visionOS + Android XR in lockstep). The wire contract is
//  the same for all three clients; only the transport differs:
//    - iPhone:        Bluetooth audio + ESang voice (this file).
//    - Android XR:    same endpoints, Android-side bridge.
//    - visionOS:      same endpoints, visionOS-side bridge.
//
//  Drop into: EusoTrip/Services/XRSessionBridge.swift
//

import Foundation
import Combine
import CryptoKit

// MARK: - Wire types

public struct XRChecklistItem: Decodable, Hashable, Identifiable, Sendable {
    public let itemId: String
    public let category: String
    public let label: String
    public let spokenPrompt: String
    public let citation: String
    public let confirmPhrases: [String]
    public let overlayState: String?
    public let required: Bool
    public let confirmed: Bool

    public var id: String { itemId }
}

public struct XRChecklistResponse: Decodable, Hashable, Sendable {
    public let loadId: Int
    public let loadNumber: String
    public let items: [XRChecklistItem]
    public let confirmedCount: Int
    public let totalCount: Int
    public let requiredCount: Int
    public let requiredRemaining: Int
}

public struct XRConfirmResponse: Decodable, Hashable, Sendable {
    public let success: Bool
    public let itemId: String
    public let overlayWritten: Bool
    public let overlayState: String?
    public let confirmationAuditId: Int?
    public let overlayAuditId: Int?
    public let signature: AstraSignatureBlock
}

// MARK: - Session phases

public enum XRSessionPhase: Equatable, Hashable, Sendable {
    case idle
    case loading
    case prompting(itemIndex: Int)
    case awaitingConfirmation(itemId: String)
    case complete
    case error(String)
}

// MARK: - Bridge

@MainActor
public final class XRSessionBridge: ObservableObject {
    public static let shared = XRSessionBridge()

    @Published public private(set) var phase: XRSessionPhase = .idle
    @Published public private(set) var checklist: XRChecklistResponse? = nil
    @Published public private(set) var currentItemIndex: Int = 0
    @Published public private(set) var lastError: String? = nil

    public init() {}

    /// Start (or resume) the pre-haul XR session for a load. Reads
    /// each item aloud in the driver's preferred dialect.
    public func start(loadId: String) async {
        phase = .loading
        lastError = nil
        struct In: Encodable { let loadId: String }
        do {
            let response: XRChecklistResponse = try await EusoTripAPI.shared.query(
                "xrChecklist.getChecklist", input: In(loadId: loadId)
            )
            checklist = response
            // Resume at the first un-confirmed item.
            let firstPending = response.items.firstIndex(where: { !$0.confirmed }) ?? response.items.count
            currentItemIndex = firstPending
            await advanceToCurrent()
        } catch {
            lastError = (error as NSError).localizedDescription
            phase = .error(lastError ?? "Unknown error")
        }
    }

    /// Driver supplied a voice transcript. Try to match the active
    /// item's confirmPhrases; on match, post to server.
    public func handleVoiceTranscript(_ transcript: String) async {
        guard let list = checklist,
              currentItemIndex < list.items.count else { return }
        let item = list.items[currentItemIndex]
        let normalised = transcript.lowercased()
        let matched = item.confirmPhrases.contains(where: { normalised.contains($0.lowercased()) })
        if !matched {
            // Re-read the current prompt — user might have said
            // something else. Keep audio context alive.
            await speak("I didn't catch that. " + item.spokenPrompt)
            return
        }
        await confirmCurrentItem(source: "voice", transcript: transcript)
    }

    /// Manual confirmation — phone-side tap. Same audit chain entry
    /// (with `source: "manual"`) as the voice path.
    public func confirmCurrentItemManually() async {
        await confirmCurrentItem(source: "manual", transcript: nil)
    }

    /// Skip the current item. Doesn't write any audit row; pre-haul
    /// gate (required items remaining) still surfaces it later.
    public func skipCurrentItem() async {
        currentItemIndex += 1
        await advanceToCurrent()
    }

    /// Cancel the session — stop TTS playback, reset phase.
    public func stop() {
        ESangTTSPlayer.shared.stop()
        phase = .idle
    }

    // MARK: - Internals

    private func advanceToCurrent() async {
        guard let list = checklist else { return }
        if currentItemIndex >= list.items.count {
            await speak("Pre-haul checklist complete. You're cleared to depart pickup.")
            phase = .complete
            return
        }
        let item = list.items[currentItemIndex]
        phase = .prompting(itemIndex: currentItemIndex)
        await speak(item.spokenPrompt)
        phase = .awaitingConfirmation(itemId: item.itemId)
    }

    private func confirmCurrentItem(source: String, transcript: String?) async {
        guard let list = checklist,
              currentItemIndex < list.items.count else { return }
        let item = list.items[currentItemIndex]
        struct In: Encodable {
            let loadId: String
            let itemId: String
            let transcript: String?
            let source: String
        }
        let payload = In(
            loadId: list.loadNumber,
            itemId: item.itemId,
            transcript: transcript,
            source: source
        )
        do {
            let result: XRConfirmResponse = try await EusoTripAPI.shared.mutation(
                "xrChecklist.confirmItem", input: payload
            )
            // Verify the Ed25519 signature locally. Reuses the same
            // CryptoKit verification path as Astra (P0-6/P0-7/P0-17).
            if !verifySignature(result.signature) {
                lastError = "Signature verification failed for the confirmation. Audit chain row was not anchored."
                await speak("Signature check failed. Please retry.")
                return
            }
            let overlayLine = result.overlayWritten && result.overlayState != nil
                ? " Overlay \(result.overlayState!) recorded."
                : ""
            await speak("Confirmed.\(overlayLine)")
            currentItemIndex += 1
            await advanceToCurrent()
        } catch {
            lastError = (error as NSError).localizedDescription
            await speak("Confirmation didn't go through. Try again or skip.")
        }
    }

    private func speak(_ text: String) async {
        await ESangTTSPlayer.shared.speak(text, serverAudioBase64: nil)
    }

    private nonisolated func verifySignature(_ sig: AstraSignatureBlock) -> Bool {
        guard
            let digest = Data(base64Encoded: sig.digestSha256B64),
            let signature = Data(base64Encoded: sig.signatureBytesB64),
            let pubKeyRaw = Data(base64Encoded: sig.publicKeyB64),
            digest.count == 32, signature.count == 64, pubKeyRaw.count == 32
        else { return false }
        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyRaw)
            return publicKey.isValidSignature(signature, for: digest)
        } catch { return false }
    }
}
