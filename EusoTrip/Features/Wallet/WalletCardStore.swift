//
//  WalletCardStore.swift
//  EusoTrip — the Apple Wallet card module's brain: choose-your-card logic +
//  the themed Add-to-Wallet hand-off.
//
//  THE LOGIC (why it's "perfect"):
//   • Source of truth = the server (users.walletThemeId). The client keeps a
//     cache for an INSTANT preview, but the server always wins.
//   • select(_:) is OPTIMISTIC (UI updates immediately), VALIDATED (only known
//     ids), IDEMPOTENT (re-tapping the current style is a no-op), COALESCED
//     (rapid taps cancel the in-flight sync; the latest wins), and ROLLS BACK
//     on failure so the UI never lies about what's saved.
//   • addToWallet(...) awaits any pending sync FIRST, so the minted pass always
//     reflects the committed choice, then downloads + presents the themed pass.
//
//  BINDINGS: calls the real EusoTripAPI (see EusoTripAPI+Wallet.swift). The
//  pkpass download routes through `api.fetchAuthenticatedData(url)` — the
//  shared, BOUNDED session (22s/120s, per the no-lingering-load rule) that also
//  attaches the bearer only for our own host (Azure Blob SAS URLs keep their
//  signature). The load id is normalized to NUMERIC before minting because the
//  server does `parseInt(loadId)` and a display id like "LD-1039" → NaN →
//  "Invalid loadId".
//
//  TARGET: EusoTrip/Features/Wallet/WalletCardStore.swift
//

import SwiftUI
import PassKit

@MainActor
final class WalletCardStore: ObservableObject {

    @Published private(set) var themes: [WalletCardTheme] = WalletCardTheme.fallback
    @Published private(set) var selectedId: String
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?

    private let api: EusoTripAPI
    private let defaults: UserDefaults
    private let key = "eusotrip.walletThemeId"
    private var syncTask: Task<Void, Never>?

    init(api: EusoTripAPI = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        self.selectedId = defaults.string(forKey: key) ?? WalletCardTheme.defaultId
    }

    /// The currently selected theme (always valid — falls back to the first).
    var selected: WalletCardTheme {
        themes.first { $0.id == selectedId } ?? themes[0]
    }

    // MARK: Load — server is the source of truth; cache/default cover offline + first launch.
    func load() async {
        if let serverThemes = try? await api.listWalletThemes(), !serverThemes.isEmpty {
            themes = serverThemes
        }
        if let ref = try? await api.getWalletTheme(), themes.contains(where: { $0.id == ref.themeId }) {
            selectedId = ref.themeId
            persist(ref.themeId)
        } else if !themes.contains(where: { $0.id == selectedId }) {
            // cached id no longer exists (retired theme) → snap to default
            selectedId = themes.first?.id ?? WalletCardTheme.defaultId
            persist(selectedId)
        }
    }

    // MARK: Select — the choose-your-card function.
    func select(_ id: String) {
        guard themes.contains(where: { $0.id == id }) else { return }   // 1. validate
        guard id != selectedId else { return }                         // 2. idempotent
        let previous = selectedId
        selectedId = id                                                // 3. optimistic
        persist(id)                                                    //    cache instantly
        errorMessage = nil

        syncTask?.cancel()                                             // 4. coalesce taps
        syncTask = Task { [weak self] in
            guard let self else { return }
            self.isSyncing = true
            defer { self.isSyncing = false }
            do {
                try Task.checkCancellation()
                _ = try await self.api.setWalletTheme(id)              // 5. commit (source of truth)
            } catch is CancellationError {
                // superseded by a newer tap — the newer task owns the final state
            } catch {
                guard self.selectedId == id else { return }            // a newer tap already moved on
                self.selectedId = previous                             // 6. roll back on failure
                self.persist(previous)
                self.errorMessage = "Couldn't save your card style. Check your connection and try again."
            }
        }
    }

    /// Retry after a failed sync without changing the visible selection.
    func retrySync() { let id = selectedId; selectedId = "__"; select(id) }

    // MARK: Add to Apple Wallet — themed pass for a specific load.
    func addToWallet(loadId: String, present: (PKAddPassesViewController) -> Void) async {
        await syncTask?.value                                          // ensure the choice is committed
        do {
            // Server keys on a numeric load id (`parseInt(loadId)`); normalize a
            // display id ("LD-1039" / "load_1039") to its digits so the mint
            // doesn't throw "Invalid loadId".
            let numericLoadId = Self.numericLoadId(from: loadId)
            let cred = try await api.createPickupCredential(loadId: numericLoadId, expiresInHours: 24)

            guard let urlString = cred.pkpassUrl, let url = URL(string: urlString) else {
                // PassKit not configured server-side → caller shows the inline QR + shortCode.
                NotificationCenter.default.post(name: .eusoFallbackToInlineQR,
                                                object: nil, userInfo: ["shortCode": cred.shortCode])
                return
            }
            // BOUNDED, auth-aware download (no raw URLSession.shared default timeout).
            let (data, _) = try await api.fetchAuthenticatedData(url)
            let pass = try PKPass(data: data)

            if PKPassLibrary().containsPass(pass) {
                errorMessage = "This pickup pass is already in your Wallet."
                return
            }
            guard let vc = PKAddPassesViewController(pass: pass) else {
                errorMessage = "Couldn't open Apple Wallet."
                return
            }
            present(vc)
        } catch {
            errorMessage = "Couldn't add to Wallet: \(error.localizedDescription)"
        }
    }

    // MARK: Add to Apple Wallet — themed STAFF ACCESS CARD (no load).
    //
    // Sibling of `addToWallet(loadId:present:)`, but for the staff access
    // credential. The server-side `terminals.createStaffAccessCredential` proc
    // (being built on the existing `staffAccessTokens` grant) signs the themed
    // pass for the caller's REAL temporary access token — the client never
    // invents an access code. When PassKit isn't configured server-side,
    // `pkpassUrl` is nil and the caller falls back to the inline QR + 6-digit
    // code (posted via `.eusoAccessFallbackToInlineQR`), never a fabricated pass.
    func addAccessCardToWallet(present: (PKAddPassesViewController) -> Void) async {
        await syncTask?.value                                          // ensure the choice is committed
        do {
            let cred = try await api.createStaffAccessCredential(themeId: selectedId, expiresInHours: 24)

            guard let urlString = cred.pkpassUrl, let url = URL(string: urlString) else {
                // PassKit not configured server-side → caller shows the inline
                // QR (cred.qrPayload) + the real 6-digit code (cred.accessCode).
                NotificationCenter.default.post(
                    name: .eusoAccessFallbackToInlineQR, object: nil,
                    userInfo: [
                        "accessCode": cred.accessCode,
                        "qrPayload":  cred.qrPayload,
                        "expiresAt":  cred.expiresAt as Any
                    ])
                return
            }
            let (data, _) = try await api.fetchAuthenticatedData(url)
            let pass = try PKPass(data: data)

            if PKPassLibrary().containsPass(pass) {
                errorMessage = "This access card is already in your Wallet."
                return
            }
            guard let vc = PKAddPassesViewController(pass: pass) else {
                errorMessage = "Couldn't open Apple Wallet."
                return
            }
            present(vc)
        } catch {
            errorMessage = "Couldn't add your access card to Wallet: \(error.localizedDescription)"
        }
    }

    /// Reduce a display load id to the digits the server's `parseInt` expects.
    /// "1039" → "1039", "LD-1039" → "1039", "load_1039" → "1039".
    private static func numericLoadId(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if Int(trimmed) != nil { return trimmed }
        let digits = trimmed.filter(\.isNumber)
        return digits.isEmpty ? trimmed : digits
    }

    private func persist(_ id: String) { defaults.set(id, forKey: key) }
}

extension Notification.Name {
    static let eusoFallbackToInlineQR = Notification.Name("eusoFallbackToInlineQR")
    /// Posted when a STAFF ACCESS CARD mint succeeds but PassKit isn't yet
    /// configured server-side (pkpassUrl == nil): the holder UI shows the
    /// inline QR (`qrPayload`) + the real 6-digit `accessCode`.
    static let eusoAccessFallbackToInlineQR = Notification.Name("eusoAccessFallbackToInlineQR")
}
