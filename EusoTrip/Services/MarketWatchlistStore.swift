//
//  MarketWatchlistStore.swift
//  EusoTrip — Session-scoped Market Intelligence watchlist (the ordered
//  set of pricing symbols the user has pinned to their grid).
//
//  Why a dedicated store (mirrors the `DriverProfileStore` rationale):
//    • `EusoTripSession` holds *auth* state — read-mostly, rotated on
//      sign-in/sign-out — and has no business carrying per-user grid
//      preferences.
//    • `MarketWatchlistStore` holds the user's *watchlist* preference:
//      which symbols they pinned, in what order, and whether they've
//      customized at all. Written when the user adds / removes / reorders
//      a symbol on the Market Intelligence surface, read by the grid that
//      decides which tiles to render.
//
//  Persistence doctrine (founder parity mandate, same as
//  `DriverProfileStore`): UserDefaults is the local cache and stays
//  AUTHORITATIVE; every mutation also syncs to the server watchlist
//  contract so the preference follows the user to web + iPad. A sync
//  failure is surfaced on `lastSyncError` while local UserDefaults
//  remains the source of truth offline.
//
//  Honest-empty rule: if the user has NEVER customized, `selectedSymbols`
//  stays empty and `customized` stays false. The grid reads that as
//  "show the full server feed" — it must NEVER render a blank grid, and
//  this store NEVER fabricates a default symbol to fill it.
//
//  Persisted to `UserDefaults` under
//  `"com.eusorone.EusoTrip.marketWatchlist.*"` so the pins survive a cold
//  launch.
//
//  Powered by ESANG AI™.
//

import Foundation
import SwiftUI

@MainActor
final class MarketWatchlistStore: ObservableObject {

    // MARK: - Published state (read by the Market Intelligence grid)

    /// The user's pinned symbols, in display order. Empty == the user has
    /// not customized; the grid then shows the full server feed. We never
    /// seed this with a fabricated default.
    @Published var selectedSymbols: [String]

    /// `true` once the user has explicitly added / removed / set / reset
    /// their watchlist. Gates `refreshFromServer()` from clobbering a
    /// local customization with a stale server snapshot.
    @Published var customized: Bool

    /// Last server sync failure. The watchlist remains locally applied even
    /// when this is non-nil; the UI can surface it as "saved on this device".
    @Published private(set) var lastSyncError: String? = nil

    // MARK: - Init

    /// Hydrate from UserDefaults synchronously (cold-start UX). If the
    /// keys are absent we leave `selectedSymbols` empty and `customized`
    /// false — so the grid shows the full server feed rather than a blank
    /// grid. A background `refreshFromServer()` then folds in the
    /// server's saved watchlist IFF the user hasn't locally customized.
    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Key.symbols),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.selectedSymbols = decoded
        } else {
            self.selectedSymbols = []
        }
        // `bool(forKey:)` returns false when the key is absent, which is
        // exactly the "never customized" default we want.
        self.customized = d.bool(forKey: Key.customized)

        // Background refresh — server can hold a watchlist saved on web /
        // iPad. Tolerated silently; the cached UserDefaults values already
        // painted the grid so the user never sees a flash.
        Task { [weak self] in
            await self?.refreshFromServer()
        }
    }

    // MARK: - Mutations (each persists locally + fires a server write)

    /// Append a symbol to the watchlist (no-op if already present).
    func add(_ symbol: String) {
        let s = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !selectedSymbols.contains(s) else { return }
        selectedSymbols.append(s)
        customized = true
        persistAndSync()
    }

    /// Remove a symbol from the watchlist.
    func remove(_ symbol: String) {
        guard selectedSymbols.contains(symbol) else { return }
        selectedSymbols.removeAll { $0 == symbol }
        customized = true
        persistAndSync()
    }

    /// Replace the entire watchlist (used by a reorder / multi-select
    /// editor). De-dupes while preserving the caller's order.
    func set(_ symbols: [String]) {
        var seen = Set<String>()
        let cleaned = symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
        selectedSymbols = cleaned
        customized = true
        persistAndSync()
    }

    /// Clear the customization entirely — the grid returns to showing the
    /// full server feed. `customized` flips back to false so a subsequent
    /// `refreshFromServer()` can fold the server's watchlist back in.
    func resetToDefault() {
        selectedSymbols = []
        customized = false
        persistAndSync()
    }

    // MARK: - Server pull

    /// Fold the server-saved watchlist into local state, but only if the
    /// user has NOT locally customized — a local customization always wins
    /// (offline-first). Server failures are exposed on `lastSyncError`.
    func refreshFromServer() async {
        // Local customization is authoritative — never let a server
        // snapshot clobber a pin the user just made.
        guard !customized else { return }

        struct Watchlist: Decodable {
            let symbols: [String]?
            let customized: Bool?
        }
        let w: Watchlist
        do {
            w = try await EusoTripAPI.shared.queryNoInput("marketPricing.getWatchlist")
            lastSyncError = nil
        } catch {
            lastSyncError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            return
        }
        // Re-check after the await — the user may have customized while
        // the round-trip was in flight.
        guard !customized else { return }

        // Only adopt the server watchlist when the server says the user
        // actually customized there. A server `customized == false` (or a
        // nil/empty list) means "no saved watchlist" → keep showing the
        // full feed; do NOT fabricate symbols.
        if w.customized == true, let symbols = w.symbols, !symbols.isEmpty {
            self.selectedSymbols = symbols
            self.customized = true
            // Mirror into UserDefaults so the next cold start renders the
            // server-adopted watchlist offline.
            let d = UserDefaults.standard
            if let data = try? JSONEncoder().encode(symbols) {
                d.set(data, forKey: Key.symbols)
            }
            d.set(true, forKey: Key.customized)
        }
    }

    // MARK: - Private

    /// Persist the current state to UserDefaults immediately (local cache
    /// is authoritative), then sync the same value to the server watchlist.
    /// A server failure never rolls back the local choice; it is surfaced
    /// through `lastSyncError`.
    private func persistAndSync() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(selectedSymbols) {
            d.set(data, forKey: Key.symbols)
        }
        d.set(customized, forKey: Key.customized)

        let snapshot = selectedSymbols
        Task {
            struct In: Encodable { let symbols: [String] }
            struct Out: Decodable { let success: Bool? }
            do {
                let out: Out = try await EusoTripAPI.shared.mutation(
                    "marketPricing.setWatchlist",
                    input: In(symbols: snapshot)
                )
                if out.success == false {
                    lastSyncError = "Market watchlist stayed saved on this device, but the sync to your account was not accepted — it will not follow you to another device yet."
                } else {
                    lastSyncError = nil
                }
            } catch {
                lastSyncError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - UserDefaults keys

    private enum Key {
        static let symbols    = "com.eusorone.EusoTrip.marketWatchlist.symbols"
        static let customized = "com.eusorone.EusoTrip.marketWatchlist.customized"
    }
}
