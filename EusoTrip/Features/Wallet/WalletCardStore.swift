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

    struct PreviewLoad: Equatable {
        let loadNumber: String
        let origin: String
        let destination: String
        let eta: String
        let equipment: String
        let carrier: String
    }

    @Published private(set) var themes: [WalletCardTheme] = WalletCardTheme.fallback
    @Published private(set) var selectedId: String
    @Published private(set) var pendingThemeId: String?
    @Published private(set) var previewLoad: PreviewLoad?
    @Published private(set) var isSyncing = false
    @Published private(set) var canRetryThemeSync = false
    @Published var errorMessage: String?

    private let api: EusoTripAPI
    private let defaults: UserDefaults
    private let key = "eusotrip.walletThemeId"
    private var syncTask: Task<Void, Never>?
    private var failedThemeId: String?
    private var liveCatalogLoaded = false

    init(api: EusoTripAPI = .shared, defaults: UserDefaults = .standard) {
        self.api = api
        self.defaults = defaults
        self.selectedId = defaults.string(forKey: key) ?? WalletCardTheme.defaultId
    }

    /// The currently selected theme (always valid — falls back to the first).
    var selected: WalletCardTheme {
        themes.first { $0.id == selectedId } ?? themes[0]
    }

    var canMintSelectedTheme: Bool {
        liveCatalogLoaded && selected.isVersioned && !isSyncing
    }

    // MARK: Load — server is the source of truth; cache/default cover offline + first launch.
    func load(loadId: String? = nil) async {
        do {
            let serverThemes = try await api.listWalletThemes()
            guard !serverThemes.isEmpty else {
                throw EusoTripAPIError.empty
            }
            themes = serverThemes
            let ref = try await api.getWalletTheme()
            guard let selectedTheme = themes.first(where: { $0.id == ref.themeId }),
                  selectedTheme.revision == ref.themeRevision,
                  selectedTheme.digest == ref.themeDigest,
                  selectedTheme.manifestVersion == ref.manifestVersion else {
                throw EusoTripAPIError.empty
            }
            selectedId = ref.themeId
            persist(ref.themeId)
            liveCatalogLoaded = true
            canRetryThemeSync = false
            errorMessage = nil
        } catch {
            liveCatalogLoaded = false
            if !themes.contains(where: { $0.id == selectedId }) {
                selectedId = themes.first?.id ?? WalletCardTheme.defaultId
                persist(selectedId)
            }
            canRetryThemeSync = true
            errorMessage = "Couldn't refresh Wallet styles: \(error.localizedDescription)"
        }

        guard let loadId else { return }
        do {
            guard let detail = try await api.loads.getDetail(id: Self.numericLoadId(from: loadId)) else {
                previewLoad = nil
                return
            }
            previewLoad = PreviewLoad(
                loadNumber: detail.loadNumber,
                origin: Self.place(detail.pickupLocation, fallback: detail.origin),
                destination: Self.place(detail.deliveryLocation, fallback: detail.destination),
                eta: Self.displayDate(detail.estimatedDeliveryDate ?? detail.deliveryDate),
                equipment: Self.nonEmpty(detail.equipmentType) ?? Self.nonEmpty(detail.cargoType) ?? "—",
                carrier: Self.nonEmpty(detail.catalyst?.companyName) ?? Self.nonEmpty(detail.catalyst?.name) ?? "—"
            )
        } catch {
            previewLoad = nil
        }
    }

    // MARK: Select — the choose-your-card function.
    func select(_ id: String) {
        guard !isSyncing,
              let theme = themes.first(where: { $0.id == id }),
              theme.isVersioned,
              liveCatalogLoaded else { return }
        guard id != selectedId else { return }
        canRetryThemeSync = false
        errorMessage = nil
        failedThemeId = nil
        startSync(theme: theme)
    }

    private func startSync(theme: WalletCardTheme) {
        guard let revision = theme.revision, let digest = theme.digest else { return }
        pendingThemeId = theme.id
        syncTask = Task { [weak self] in
            guard let self else { return }
            self.isSyncing = true
            defer {
                self.isSyncing = false
                self.pendingThemeId = nil
            }
            do {
                let committed = try await self.api.setWalletTheme(theme.id, revision: revision)
                guard committed.ok,
                      committed.themeId == theme.id,
                      committed.themeRevision == revision,
                      committed.themeDigest == digest,
                      committed.manifestVersion == theme.manifestVersion else {
                    throw WalletPassValidationError.themeMismatch
                }
                self.selectedId = theme.id
                self.persist(theme.id)
                self.canRetryThemeSync = false
            } catch {
                self.failedThemeId = theme.id
                self.canRetryThemeSync = true
                self.errorMessage = "Couldn't save your card style. Check your connection and try again."
            }
        }
    }

    /// Retry after a failed sync without changing the visible selection.
    func retrySync() {
        canRetryThemeSync = false
        errorMessage = nil
        guard let id = failedThemeId,
              let theme = themes.first(where: { $0.id == id }) else { return }
        startSync(theme: theme)
    }

    // MARK: Add to Apple Wallet — themed pass for a specific load.
    func addToWallet(loadId: String, present: (PKAddPassesViewController) -> Void) async {
        await syncTask?.value                                          // ensure the choice is committed
        canRetryThemeSync = false
        do {
            let chosenTheme = selected
            guard liveCatalogLoaded,
                  let revision = chosenTheme.revision,
                  let digest = chosenTheme.digest else {
                throw WalletPassValidationError.catalogUnavailable
            }
            // Server keys on a numeric load id (`parseInt(loadId)`); normalize a
            // display id ("LD-1039" / "load_1039") to its digits so the mint
            // doesn't throw "Invalid loadId".
            let numericLoadId = Self.numericLoadId(from: loadId)
            let cred = try await api.createPickupCredential(
                loadId: numericLoadId,
                expiresInHours: 24,
                themeId: chosenTheme.id,
                themeRevision: revision
            )

            guard let urlString = cred.pkpassUrl, let url = URL(string: urlString) else {
                // PassKit not configured server-side → caller shows the inline QR + shortCode.
                NotificationCenter.default.post(name: .eusoFallbackToInlineQR,
                                                object: nil, userInfo: ["shortCode": cred.shortCode])
                return
            }
            guard cred.passkitStatus == "signed",
                  let signedTheme = cred.signedTheme,
                  signedTheme.id == chosenTheme.id,
                  signedTheme.revision == revision,
                  signedTheme.digest == digest,
                  cred.theme == signedTheme,
                  !(cred.manifestDigest ?? "").isEmpty else {
                throw WalletPassValidationError.themeMismatch
            }
            // BOUNDED, auth-aware download (no raw URLSession.shared default timeout).
            let (data, _) = try await api.fetchAuthenticatedData(url)
            let pass = try PKPass(data: data)
            guard pass.userInfo["walletThemeId"] as? String == chosenTheme.id,
                  pass.userInfo["walletThemeRevision"] as? String == revision,
                  pass.userInfo["walletThemeDigest"] as? String == digest,
                  pass.userInfo["walletThemeManifestVersion"] as? String == chosenTheme.manifestVersion,
                  pass.userInfo["walletThemePassStyle"] as? String == chosenTheme.passStyle else {
                throw WalletPassValidationError.themeMismatch
            }

            let library = PKPassLibrary()
            if library.containsPass(pass) {
                guard library.replacePass(with: pass) else {
                    errorMessage = "Couldn't update the pickup pass already in Wallet."
                    return
                }
                errorMessage = "Your Wallet pass now uses \(selected.name)."
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
        canRetryThemeSync = false
        do {
            let chosenTheme = selected
            guard liveCatalogLoaded,
                  let revision = chosenTheme.revision,
                  let digest = chosenTheme.digest else {
                throw WalletPassValidationError.catalogUnavailable
            }
            let cred = try await api.createStaffAccessCredential(
                themeId: chosenTheme.id,
                themeRevision: revision,
                expiresInHours: 24
            )

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
            guard cred.passkitStatus == "signed",
                  let signedTheme = cred.signedTheme,
                  signedTheme.id == chosenTheme.id,
                  signedTheme.revision == revision,
                  signedTheme.digest == digest,
                  cred.theme == signedTheme,
                  !(cred.manifestDigest ?? "").isEmpty else {
                throw WalletPassValidationError.themeMismatch
            }
            let (data, _) = try await api.fetchAuthenticatedData(url)
            let pass = try PKPass(data: data)
            guard pass.userInfo["walletThemeId"] as? String == chosenTheme.id,
                  pass.userInfo["walletThemeRevision"] as? String == revision,
                  pass.userInfo["walletThemeDigest"] as? String == digest,
                  pass.userInfo["walletThemeManifestVersion"] as? String == chosenTheme.manifestVersion,
                  pass.userInfo["walletThemePassStyle"] as? String == "eventTicket" else {
                throw WalletPassValidationError.themeMismatch
            }

            let library = PKPassLibrary()
            if library.containsPass(pass) {
                guard library.replacePass(with: pass) else {
                    errorMessage = "Couldn't update the access card already in Wallet."
                    return
                }
                errorMessage = "Your Wallet access card now uses \(selected.name)."
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

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func place(_ primary: LoadsAPI.LoadCityState?, fallback: LoadsAPI.LoadAddress?) -> String {
        if let cityState = nonEmpty(primary?.cityState) { return cityState }
        return [fallback?.city, fallback?.state]
            .compactMap(nonEmpty)
            .joined(separator: ", ")
            .nilIfEmpty ?? "—"
    }

    private static func displayDate(_ iso: String?) -> String {
        guard let iso = nonEmpty(iso) else { return "—" }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = precise.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func persist(_ id: String) { defaults.set(id, forKey: key) }
}

private enum WalletPassValidationError: LocalizedError {
    case catalogUnavailable
    case themeMismatch

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            return "Refresh Wallet styles before adding this pass."
        case .themeMismatch:
            return "The signed Apple Wallet pass did not match the selected design."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Notification.Name {
    static let eusoFallbackToInlineQR = Notification.Name("eusoFallbackToInlineQR")
    /// Posted when a STAFF ACCESS CARD mint succeeds but PassKit isn't yet
    /// configured server-side (pkpassUrl == nil): the holder UI shows the
    /// inline QR (`qrPayload`) + the real 6-digit `accessCode`.
    static let eusoAccessFallbackToInlineQR = Notification.Name("eusoAccessFallbackToInlineQR")
}
