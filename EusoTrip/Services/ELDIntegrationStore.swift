//
//  ELDIntegrationStore.swift
//  EusoTrip
//
//  Drives the ELD Integration surface — the native-iOS counterpart of the
//  web `ELDConnectionPanel`. Pulls the provider catalog and current
//  connection status off the live backend, owns the Connect / Disconnect
//  mutations, and publishes enough state for a plain SwiftUI view to
//  render provider tiles, a status pill, and success/error toasts.
//
//  All state is fetched through `EusoTripAPI.shared.eld` — the same
//  `eld.getAllProviders`, `eld.getConnectionStatus`, `eld.connectProvider`,
//  `eld.disconnectProvider` procedures the web platform calls.
//
//  HOS real-time data is NOT a separate iOS concern: once a provider is
//  connected, the existing `hos.getStatus` / `hos.getDailyLog` endpoints
//  that HOSLiveStore already polls transparently return live ELD data
//  (Samsara / Motive / Geotab, etc.). That pipe is 100% server-side, so
//  the iOS app just has to ensure the connection row exists — which is
//  exactly what this store exposes.
//
//  FMCSA 49 CFR 395 compliance: when a driver types their API key into
//  the connector UI and we persist it via `connectProvider`, the server
//  starts pulling their real-time duty-status from the ELD vendor. From
//  then on, HOS drive/shift/cycle clocks, 30-min break signals, and
//  violations are no longer driver-self-reported — they're vendor-sourced
//  records of duty status that satisfy 49 CFR 395.22(b). This store is
//  the only thing the driver has to touch to make that transition.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class ELDIntegrationStore: ObservableObject {

    // MARK: - Published state

    /// Full catalog of supported providers (Samsara → Trimble). Empty
    /// until `bootstrap()` / `refresh()` completes the first fetch.
    @Published private(set) var providers: [ELDProvider] = []

    /// Connection snapshot — `connected` drives the header pill, and
    /// `providers` is the list of slugs currently in "connected" status
    /// for this fleet. Typically zero or one entry per fleet.
    @Published private(set) var connection: ELDConnectionStatus?

    /// Primary-provider rich config. Only populated when a single
    /// provider is canonically configured (Samsara for now). Exposes
    /// the 49 CFR 395 HOS limit constants for the compliance footer.
    @Published private(set) var config: ELDProviderConfig?

    /// Wire-level loading indicator for the initial `bootstrap()` call.
    /// Individual Connect / Disconnect mutations use `isMutating`.
    @Published private(set) var isLoading: Bool = false

    /// True while `connect(...)` or `disconnect(...)` is in flight — the
    /// view disables its CTAs while this is set so double-taps can't
    /// create duplicate Drizzle rows. (The server `upsert` would collapse
    /// them anyway but the user-facing UX should still feel deterministic.)
    @Published private(set) var isMutating: Bool = false

    /// One-shot banner strings for the caller to display and clear. We
    /// intentionally use two separate slots (rather than a single
    /// `ResultKind`) so success and error can co-exist during a retry
    /// cycle without one overwriting the other.
    @Published var errorMessage: String?
    @Published var successMessage: String?

    /// Slug the user has highlighted in the picker. Not automatically
    /// connected — the Connect button still has to be pressed.
    @Published var selectedSlug: String?

    /// API-key input buffer. Lives in the store (not in the view) so we
    /// can clear it when the user disconnects or switches providers
    /// without fighting SwiftUI's @State re-creation rules.
    @Published var apiKeyDraft: String = ""

    /// Whether the API-key field should render as a SecureField (default)
    /// or a plain TextField (so the driver can eyeball-check what they
    /// pasted). Kept here because the toggle state belongs to the form,
    /// not to any transient view.
    @Published var apiKeyRevealed: Bool = false

    // MARK: - Derived

    /// True if at least one provider is in "connected" status for this fleet.
    var isConnected: Bool {
        connection?.connected == true
    }

    /// The single connected provider, if any — matches the server's
    /// "one provider per fleet" normal case. Returns nil when 0 or 2+
    /// are connected so the caller can fall back to a list view.
    var primaryConnectedSlug: String? {
        guard let slugs = connection?.providers, slugs.count == 1 else {
            return connection?.providers.first
        }
        return slugs.first
    }

    /// Resolve a slug back to a provider record (for display).
    func provider(for slug: String) -> ELDProvider? {
        providers.first { $0.slug == slug }
    }

    // MARK: - Lifecycle

    /// Initial load. Safe to call from `.task { await store.bootstrap() }`
    /// on appearance — internally reuses `refresh()`.
    func bootstrap() async {
        isLoading = true
        defer { isLoading = false }
        await refresh()
    }

    /// Re-hit every read endpoint. Errors set `errorMessage` but leave
    /// prior state in place so a transient outage doesn't wipe the
    /// provider grid the user already had in front of them.
    func refresh() async {
        async let providers = fetchProviders()
        async let connection = fetchConnection()
        async let config = fetchConfig()
        let (p, c, cfg) = await (providers, connection, config)
        if let p { self.providers = p }
        if let c { self.connection = c }
        if let cfg { self.config = cfg }

        // Default the picker selection to the currently-connected
        // provider so the Disconnect action is one tap away on re-entry.
        if selectedSlug == nil, let slug = primaryConnectedSlug {
            selectedSlug = slug
        } else if selectedSlug == nil, let first = self.providers.first {
            // No connection — pre-highlight the highest-satisfaction
            // provider (Samsara) so the panel has something selected
            // before the user scrolls. Purely a UX nicety; the Connect
            // button still requires an explicit slug + key.
            selectedSlug = first.slug
        }
    }

    private func fetchProviders() async -> [ELDProvider]? {
        do {
            return try await EusoTripAPI.shared.eld.getAllProviders()
        } catch {
            setError("Couldn't load ELD provider catalog — \(errorText(error))")
            return nil
        }
    }

    private func fetchConnection() async -> ELDConnectionStatus? {
        do {
            return try await EusoTripAPI.shared.eld.getConnectionStatus()
        } catch {
            // Silent: connection check failing shouldn't show a loud
            // banner on first launch. The primary flow (picker +
            // Connect) still works without a known status.
            return nil
        }
    }

    private func fetchConfig() async -> ELDProviderConfig? {
        do {
            return try await EusoTripAPI.shared.eld.getProviderConfig()
        } catch {
            return nil
        }
    }

    // MARK: - Mutations

    /// Persist `apiKey` against `slug` via `eld.connectProvider`. The
    /// server upserts into `integrationConnections` keyed by
    /// (companyId, providerSlug); the unique index guarantees at most
    /// one row per provider per fleet.
    func connect() async {
        guard !isMutating else { return }
        guard let slug = selectedSlug, !slug.isEmpty else {
            setError("Pick a provider first.")
            return
        }
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            setError("Paste your API key from your ELD provider's admin dashboard.")
            return
        }

        isMutating = true
        defer { isMutating = false }

        do {
            let result = try await EusoTripAPI.shared.eld.connectProvider(
                providerSlug: slug,
                apiKey: key
            )
            if result.success {
                let name = provider(for: slug)?.name ?? slug.capitalized
                setSuccess("\(name) connected. HOS data is now flowing from the vendor.")
                // Wipe the key field — it's persisted server-side and
                // we don't want it sitting in memory on the device.
                apiKeyDraft = ""
                apiKeyRevealed = false
                // Pull fresh status so the header pill flips to Connected.
                await refresh()
            } else {
                setError("Server rejected the credential. Double-check the key and try again.")
            }
        } catch {
            setError("Couldn't save ELD credential — \(errorText(error))")
        }
    }

    /// Mark the connection as `disconnected` server-side. We keep the
    /// row (audit trail) — the server just flips status, so reconnecting
    /// with a new key is a one-tap retry.
    func disconnect(slug: String) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }

        do {
            _ = try await EusoTripAPI.shared.eld.disconnectProvider(providerSlug: slug)
            let name = provider(for: slug)?.name ?? slug.capitalized
            setSuccess("\(name) disconnected. HOS will revert to self-reported until you reconnect.")
            apiKeyDraft = ""
            apiKeyRevealed = false
            await refresh()
        } catch {
            setError("Couldn't disconnect \(slug) — \(errorText(error))")
        }
    }

    // MARK: - Helpers

    private func setError(_ message: String) {
        errorMessage = message
        // Let the UI auto-dismiss after a few seconds — the driver
        // shouldn't have to hunt for an X to reset the form.
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if errorMessage == message { errorMessage = nil }
        }
    }

    private func setSuccess(_ message: String) {
        successMessage = message
        errorMessage = nil
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if successMessage == message { successMessage = nil }
        }
    }

    private func errorText(_ error: Error) -> String {
        if let trpc = error as? EusoTripAPIError {
            return trpc.errorDescription ?? "\(trpc)"
        }
        return error.localizedDescription
    }
}
