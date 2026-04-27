//
//  ConvoyRosterReconciler.swift
//  EusoTrip Pulse Watch App
//
//  F13 — Upgrades TOFU-pinned convoy peer keys to roster-verified
//  trust states by batching the pinned set, posting through the
//  iOS companion to `fleet.verifyConvoyMember`, and routing the
//  per-driver result back into `ConvoySignature.setTrustState`.
//
//  Design notes:
//
//    • The reconciler is the ONLY caller of
//      `WatchConnectivityManager.verifyConvoyRoster`, so there's
//      exactly one place in the codebase where pinned keys leave
//      the device. Anything that wants a verified view of the
//      convoy roster waits on `ConvoySignature.trustState(for:)`.
//
//    • Cadence is deliberately slow — 5 minutes between passes.
//      The roster doesn't change often, and the wrist's cellular
//      budget is better spent on load-state events than on ticking
//      a verify-every-peer loop. A single manual `reconcileNow()`
//      entry-point lets the convoy detail view trigger an
//      on-demand refresh when the user opens it.
//
//    • Suspect peers are re-checked each pass — an escort who
//      left the company and rejoined shouldn't be stuck with a
//      red flag forever. Unknown peers get dropped after one
//      negative confirmation; see `applyResults`.
//
//    • Confirmed peers are skipped by default to avoid flooding
//      the server. A `forceFullSweep()` entry-point lets the
//      sign-in flow (company-switch, role-change) request a
//      clean-slate re-verification.
//
//  Lifecycle: `start()` is called once from EusoTripWatchApp after
//  ConvoySignature.bootstrap(). `stop()` is idempotent. All state
//  changes happen on @MainActor for thread safety — the work is
//  negligible and keeps the mental model simple.
//

import Foundation
import Combine

@MainActor
final class ConvoyRosterReconciler {
    static let shared = ConvoyRosterReconciler()

    /// Cadence between passes. 5 minutes is a compromise between
    /// "keep trust states fresh" and "don't pound the companion's
    /// cellular radio." The sign-in path can request an immediate
    /// pass via `reconcileNow()`.
    private let passCadence: TimeInterval = 5 * 60

    /// How many pinned peers we'll verify in a single pass. Matches
    /// the server's Zod schema ceiling.
    private let batchCeiling = 64

    private var loopTask: Task<Void, Never>?
    private var isStarted = false

    /// When true, the next pass ignores the trust-state filter and
    /// re-verifies every pinned peer. Set by `forceFullSweep()`.
    private var forceFull = false

    // MARK: - Lifecycle

    /// Begin the periodic reconciliation loop. Safe to call multiple
    /// times; subsequent calls are no-ops. Gated by the global
    /// convoy feature flag so a shipper-role wrist never talks to
    /// the companion about convoys.
    func start() {
        guard EusoTripConfig.convoyEnabled else { return }
        guard !isStarted else { return }
        isStarted = true
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassSafely()
                try? await Task.sleep(
                    nanoseconds: UInt64(self.passCadence * 1_000_000_000)
                )
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isStarted = false
    }

    /// Fire a reconciliation pass immediately. The convoy detail
    /// view calls this when it opens so the roster state under
    /// "Members" is fresh instead of whatever the last periodic
    /// pass produced.
    func reconcileNow() {
        Task { [weak self] in await self?.runPassSafely() }
    }

    /// Forget every confirmation/suspect verdict we have and re-verify
    /// the whole pinned set on the next pass. Called from the sign-in
    /// flow (company switch, role change) where stale confirmations
    /// are worse than a temporary red-flag pass.
    func forceFullSweep() {
        forceFull = true
        reconcileNow()
    }

    // MARK: - Pass

    private func runPassSafely() async {
        // Wrap in do/catch so a transport error can't kill the loop.
        // Any throw here would propagate up and cancel the Task; the
        // periodic cadence is meant to survive intermittent failures.
        do {
            try await runPass()
        } catch {
            // Deliberately swallow. The next pass will retry.
        }
    }

    private func runPass() async throws {
        let all = ConvoySignature.shared.pinnedEntries()
        guard !all.isEmpty else { return }

        // Pick the batch. Default: `.unknown` + `.suspect`. A suspect
        // peer might re-join the company and deserve re-upgrade, so
        // we re-check them on every pass. Confirmed peers are only
        // re-verified on a forced full sweep.
        let candidates: [ConvoySignature.PinnedEntry]
        if forceFull {
            candidates = Array(all.prefix(batchCeiling))
            forceFull = false
        } else {
            candidates = all
                .filter { $0.trust != .confirmed }
                .prefix(batchCeiling)
                .map { $0 }
        }
        guard !candidates.isEmpty else { return }

        let request: [(driverId: String, pinnedPublicKeyB64: String)] = candidates.map {
            ($0.driverId, $0.pinnedPublicKeyB64)
        }
        let map = await WatchConnectivityManager.shared.verifyConvoyRoster(request)
        guard !map.isEmpty else { return }   // phone unreachable / failure — retry on next pass

        applyResults(map)
    }

    private func applyResults(_ map: [String: String]) {
        let sig = ConvoySignature.shared
        for (driverId, raw) in map {
            switch raw {
            case "confirmed":
                sig.setTrustState(.confirmed, for: driverId)
            case "suspect":
                sig.setTrustState(.suspect, for: driverId)
            default:
                // "unknown" — driverId doesn't resolve on any roster.
                // Drop the pin entirely so a future envelope from the
                // same driverId re-TOFUs rather than silently
                // verifying against a stale key we can't corroborate.
                sig.dropPin(for: driverId)
            }
        }
    }
}
