//
//  OrbStateMachine.swift
//  EusoTrip Pulse Watch App
//
//  L3 — the single source of truth for orb pairing lifecycle. Replaces
//  the inline `pairingInFlight` flag + 1.5 s Task in HomeView.
//
//  States progress bootingPermissions → unpairedPairing → (auth lands
//  → idleSignedIn) OR (1.5 s timeout → unpairedReady) → tap routes
//  through EsangSession.startListening which either dispatches to
//  backend (signed in) or falls through to VoiceDispatch + OfflineQueue
//  (offline / unpaired).
//
//  Critical offline-first contract (from EusoTrip_Offline_Mode_Encyclopedia
//  Chapter 06 F04): when the pairing deadline fires and no token has
//  arrived, the orb transitions to `unpairedReady` — NOT `.error` —
//  so taps proceed immediately into VoiceDispatch + OfflineQueue
//  instead of being swallowed by an error card. The orb is never
//  silent, never stuck on "Pairing…"
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class OrbStateMachine: ObservableObject {
    enum State: Equatable {
        case bootingPermissions
        case unpairedPairing
        case unpairedReady
        case idleSignedIn
        case listening
        case thinking
        case done
        case error(String)
    }

    @Published private(set) var state: State = .bootingPermissions
    @Published private(set) var lastTransitionAt: Date = Date()

    /// Whether the network path is currently satisfied. Updated by the
    /// NWPathMonitor plumbed inside OfflineQueue. Drives the "Offline"
    /// capsule rendered by HomeView under `unpairedReady` / idle.
    @Published var networkReachable: Bool = true

    /// Whether the paired iPhone is reachable via WCSession. Mirrored
    /// from `WatchConnectivityManager.isReachable` so the OFFLINE
    /// capsule respects the wrist↔phone link, not just direct cellular.
    /// Without this the orb showed OFFLINE whenever the watch was
    /// briefly unpaired-pairing (cold launch) even though the phone
    /// was right there, signed in and reachable — which is what the
    /// driver was reporting ("phone says connected, watch says
    /// offline").
    @Published var phoneReachable: Bool = false

    private var pairingDeadline: Task<Void, Never>?

    static let shared = OrbStateMachine()
    private init() {}

    /// Called on first view appear (and after any auth change).
    func appeared(signedIn: Bool) {
        if signedIn {
            transition(.idleSignedIn)
            pairingDeadline?.cancel()
        } else {
            transition(.unpairedPairing)
            armPairingDeadline()
        }
    }

    /// Called when AuthStore.isSignedIn flips true — cancels the
    /// pairing deadline and settles the orb into idle.
    func authReady() {
        pairingDeadline?.cancel()
        pairingDeadline = nil
        transition(.idleSignedIn)
    }

    /// Called when AuthStore.isSignedIn flips false (explicit sign-out
    /// or cleared token). Re-arms the pairing deadline so the orb
    /// lands in unpairedReady after 1.5s and remains tappable.
    func authLost() {
        transition(.unpairedPairing)
        armPairingDeadline()
    }

    /// Mirrors the underlying EsangSession.state into the machine's
    /// operating states so the hint line can read a single source.
    func mirrorEsang(_ s: EsangState) {
        switch s {
        case .idle:
            // Only clobber idle when we're NOT in a pairing or error
            // state — otherwise the session's idle state would
            // overwrite a legitimate pairing banner.
            if case .listening = state { transition(.idleSignedIn) }
            if case .thinking = state { transition(.idleSignedIn) }
            if case .done = state { transition(.idleSignedIn) }
            if case .error = state { /* keep */ }
        case .listening: transition(.listening)
        case .thinking:  transition(.thinking)
        case .done:      transition(.done)
        case .error(let msg): transition(.error(msg))
        }
    }

    // MARK: - Deadline

    private func armPairingDeadline() {
        pairingDeadline?.cancel()
        pairingDeadline = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            if case .unpairedPairing = self.state {
                // 1.5s elapsed and still no token — flip to
                // unpairedReady so the orb is fully interactive and the
                // hint line reads "Tap to ask" with an OFFLINE capsule.
                self.transition(.unpairedReady)
            }
        }
    }

    // MARK: - Internal

    private func transition(_ to: State) {
        if state != to {
            OrbLog.transition(state, to)
            state = to
            lastTransitionAt = Date()
        }
    }

    // MARK: - Derived

    /// Bottom-hint string. Never "Pairing…" past the 1.5 s watchdog;
    /// the default always collapses to "Tap to ask" so the orb reads
    /// as live.
    var hint: String {
        switch state {
        case .bootingPermissions: return "Starting…"
        case .unpairedPairing:    return "Pairing…"
        case .unpairedReady:      return "Tap to ask"
        case .idleSignedIn:       return "Tap to ask"
        case .listening:          return "Listening…"
        case .thinking:           return "Thinking…"
        case .done:               return "Done."
        case .error(let s):       return s
        }
    }

    /// True when the orb should render the small "OFFLINE" capsule
    /// next to the hint. We only flip OFFLINE when EVERY transport is
    /// down — neither direct cellular (`networkReachable`) nor the
    /// iPhone bridge (`phoneReachable`) can reach the backend.
    /// Previously this lit up purely based on `state` being unpaired,
    /// even when the phone was sitting right there reachable —
    /// which gave the user the "phone says connected, watch says
    /// offline" mismatch.
    var showOfflineCapsule: Bool {
        // Truly offline ↔ no direct net AND no phone bridge.
        !networkReachable && !phoneReachable
    }
}
