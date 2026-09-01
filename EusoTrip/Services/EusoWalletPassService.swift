//
//  EusoWalletPassService.swift
//  EusoTrip — Apple Wallet integration for load pickup credentials.
//
//  Founder mandate 2026-05-06: tapping a pass in the EusoWallet
//  surface must hand off to Apple Wallet via PassKit, NOT open a web
//  browser with an error screen. This service owns the .pkpass
//  download → `PKAddPassesViewController` flow.
//
//  Server contract (mirrors the web platform's portalAccessTokens
//  pattern in `frontend/server/routers/customerPortal.ts`):
//
//    `eusoWallet.createPickupCredential` →
//      {
//        loadId: String,
//        accessToken: String,        // long-form (signed, server-side)
//        shortCode: String,          // 5-digit fallback when QR
//                                     //   scanning fails (e.g. cracked
//                                     //   yard-worker phone, no camera
//                                     //   permissions)
//        pkpassUrl: String?,         // signed PKPass bundle URL on Azure
//                                     //   Blob; nil while the signing
//                                     //   pipeline is offline. UI falls
//                                     //   back to inline QR + shortCode
//                                     //   so the credential remains
//                                     //   useful even without a wallet
//                                     //   add.
//        expiresAt: String           // ISO-8601 UTC
//      }
//
//  Tap path:
//    1. UI calls `EusoWalletPassService.shared.addPass(forLoadId:)`
//    2. Service requests credential from server
//    3. If pkpassUrl present → fetch bytes, parse with `PKPass(data:)`,
//       present `PKAddPassesViewController` over the topmost view
//       controller. Apple Wallet UI takes over.
//    4. If pkpassUrl absent / 404 / sign-fail → return
//       `.signingUnavailable(qrPayload, shortCode)` so the caller can
//       render the in-app credential card (the canonical fallback the
//       web platform uses too).
//
//  Powered by ESANG AI™.
//

import Foundation
import PassKit
import UIKit

/// One Add-to-Wallet attempt result. The caller is expected to handle
/// every case — silent failure is forbidden per [feedback_zero_stubs].
enum EusoWalletPassResult {
    /// Pass successfully presented to the user (the system Apple
    /// Wallet sheet was shown). The user may still cancel; we don't
    /// model that distinction here because PassKit itself doesn't
    /// expose a clean signal for it.
    case presented
    /// A pass with the same serial number was already installed, so Wallet
    /// replaced it in place with the newly signed theme and current fields.
    case updated
    /// The server returned a credential without a `.pkpass` bundle —
    /// usually because the signing pipeline is offline or the load
    /// hasn't been activated yet. Callers render the inline credential
    /// card with the QR payload + short code instead.
    case signingUnavailable(qrPayload: String, shortCode: String)
    /// Network / decode / PassKit error. `message` is human-readable,
    /// safe to surface verbatim in a toast.
    case failure(message: String)
}

@MainActor
final class EusoWalletPassService {

    static let shared = EusoWalletPassService()
    private var activeAddPassController: PKAddPassesViewController?
    private var transportRegistration: AppRadioSilenceDirectTransportController.Registration?
    private init() {}

    /// Normalize only the display-id forms the app actually emits. Never
    /// concatenate arbitrary digits: `LD-10-39` must not become database load
    /// 1039 and accidentally target a different credential.
    static func numericLoadId(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) { return trimmed }

        let lowercased = trimmed.lowercased()
        for prefix in ["ld-", "load_", "load-"] where lowercased.hasPrefix(prefix) {
            let suffix = String(trimmed.dropFirst(prefix.count))
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) { return suffix }
        }
        return trimmed
    }

    /// Exact live selection sent back to the mint route. Keeping the revision
    /// with the id prevents a stale catalog row from silently producing the
    /// wrong art while the picker and server refresh concurrently.
    private struct ThemeSelection {
        let id: String
        let revision: String
    }

    /// Mint a credential and try to add it to Apple Wallet. The tap
    /// path is end-to-end here — no view controller wiring required by
    /// the caller. Returns a `EusoWalletPassResult` so the call site
    /// can render the right UX (toast, inline fallback, error banner).
    func addPass(forLoadId loadId: String) async -> EusoWalletPassResult {
        guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else {
            return .failure(message: "Apple Wallet is paused while the offline journey is active.")
        }
        // 0. Normalize the app's known display ids. Unknown or malformed
        //    forms remain untouched and fail the server's strict numeric-id
        //    contract instead of being lossy-converted to another load.
        let resolvedLoadId = Self.numericLoadId(from: loadId)

        // 1. Mint the credential server-side. The server signs the QR
        //    payload, generates a 5-digit shortCode, and (when the
        //    signing pipeline is healthy) uploads a .pkpass bundle to
        //    Azure Blob and returns its presigned URL.
        let requestedTheme: ThemeSelection
        do {
            requestedTheme = try await currentThemeSelection()
        } catch {
            return .failure(
                message: "Couldn't verify your selected Wallet design. Refresh Wallet styles and try again."
            )
        }
        let credential: EusoTripAPI.PickupCredential
        do {
            do {
                credential = try await EusoTripAPI.shared.createPickupCredential(
                    loadId: resolvedLoadId,
                    themeId: requestedTheme.id,
                    themeRevision: requestedTheme.revision
                )
            } catch {
                guard Self.isThemeCatalogConflict(error) else {
                    throw error
                }
                // The catalog may have advanced between the read and mint.
                // Refresh the exact versioned selection once; never ask the
                // signer to silently substitute its default design.
                let refreshedTheme: ThemeSelection
                do {
                    refreshedTheme = try await currentThemeSelection()
                } catch {
                    throw WalletPassContractError(
                        message: "Wallet styles changed and couldn't be refreshed. Refresh styles and try again."
                    )
                }
                credential = try await EusoTripAPI.shared.createPickupCredential(
                    loadId: resolvedLoadId,
                    themeId: refreshedTheme.id,
                    themeRevision: refreshedTheme.revision
                )
            }
        } catch {
            // The server is the sole credential authority. Surface its real
            // failure; never substitute a locally invented pass or QR token.
            let msg: String
            if let api = error as? EusoTripAPIError {
                switch api {
                case .unauthenticated:
                    msg = "Sign in again to mint a wallet credential."
                case .forbidden(let m):
                    msg = m
                case .trpcError(let m): msg = m
                case .httpStatus(let c, _): msg = "Server error \(c). Try again."
                default: msg = "Couldn't reach the credential service."
                }
            } else { msg = error.localizedDescription }
            return .failure(message: msg)
        }
        guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else {
            return .failure(message: "Apple Wallet is paused while the offline journey is active.")
        }

        // 2. If the server didn't ship a .pkpass bundle (signing
        //    pipeline offline, free-tier dev account, etc.), short-
        //    circuit to the inline QR + shortCode UI. The credential
        //    is still valid — the gate worker scans the QR or types
        //    the 5-digit shortCode into the receiving party's web
        //    portal.
        let passURLText = credential.pkpassUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPassURL = !(passURLText?.isEmpty ?? true)
        let signedPassAvailable: Bool
        do {
            signedPassAvailable = try Self.signedPassAvailable(
                status: credential.passkitStatus,
                hasPassURL: hasPassURL
            )
        } catch let contractError as WalletPassContractError {
            return .failure(message: contractError.message)
        } catch {
            return .failure(message: "Wallet pass availability could not be verified. Try again.")
        }
        guard signedPassAvailable else {
            return .signingUnavailable(
                qrPayload: credential.accessToken,
                shortCode: credential.shortCode
            )
        }
        guard let urlStr = passURLText, let url = URL(string: urlStr) else {
            return .failure(message: "The credential service returned an invalid Wallet pass URL.")
        }
        guard credential.passkitStatus == "signed",
              let signedTheme = credential.signedTheme,
              signedTheme == credential.theme,
              !(credential.manifestDigest ?? "").isEmpty else {
            return .failure(message: "The signed pass did not match the selected Wallet design.")
        }
        guard let expectedPassType = credential.passTypeIdentifier?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !expectedPassType.isEmpty,
              let expectedSerial = credential.passSerialNumber?.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !expectedSerial.isEmpty else {
            return .failure(message: "The signed pass did not include its credential identity.")
        }

        return await addPass(
            from: url,
            expectedTheme: signedTheme,
            expectedPassTypeIdentifier: expectedPassType,
            expectedSerialNumber: expectedSerial
        )
    }

    /// Download and install an already-minted pass URL. This is shared by the
    /// wallet picker, BOL wallet screen, and document viewer so duplicate-pass
    /// replacement and download security cannot drift between entry points.
    func addPass(from url: URL,
                 expectedTheme: EusoTripAPI.WalletThemeMetadata,
                 expectedPassTypeIdentifier: String,
                 expectedSerialNumber: String) async -> EusoWalletPassResult {
        guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else {
            return .failure(message: "Apple Wallet is paused while the offline journey is active.")
        }
        // Pull through the app's bounded, auth-aware transport. It adds the
        // bearer only for EusoTrip hosts and leaves Azure SAS URLs untouched.
        let data: Data
        do {
            data = try await EusoTripAPI.shared.fetchBoundedWalletPassData(url)
        } catch {
            return .failure(message: "Couldn't download the wallet pass.")
        }
        guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else {
            return .failure(message: "Apple Wallet is paused while the offline journey is active.")
        }

        // 4. Parse with PassKit. `PKPass(data:)` validates the bundle
        //    signature against Apple's certificate chain — a tampered
        //    or expired-cert pass throws here.
        let pkpass: PKPass
        do {
            pkpass = try PKPass(data: data)
        } catch {
            return .failure(message: "This wallet pass failed signature validation.")
        }
        guard Self.hasAuthenticatedUpdateChannel(pkpass) else {
            return .failure(message: "This wallet pass is missing its secure update channel.")
        }
        let expectedPassType = expectedPassTypeIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let expectedSerial = expectedSerialNumber.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !expectedPassType.isEmpty,
              !expectedSerial.isEmpty,
              pkpass.passTypeIdentifier == expectedPassType,
              pkpass.serialNumber == expectedSerial else {
            return .failure(message: "The downloaded pass did not match this credential.")
        }
        guard Self.matches(pkpass, expectedTheme: expectedTheme) else {
            return .failure(message: "The downloaded pass did not match the selected Wallet design.")
        }

        // 5. A theme change keeps the same pass serial number. Apple Wallet
        //    therefore needs an explicit replacement; presenting another add
        //    sheet leaves the old design installed and may reject a duplicate.
        let library = PKPassLibrary()
        if library.containsPass(pkpass) {
            guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else {
                return .failure(message: "Apple Wallet is paused while the offline journey is active.")
            }
            guard library.replacePass(with: pkpass),
                  let installed = library.pass(
                    withPassTypeIdentifier: expectedPassType,
                    serialNumber: expectedSerial
                  ),
                  installed.passTypeIdentifier == expectedPassType,
                  installed.serialNumber == expectedSerial,
                  Self.matches(installed, expectedTheme: expectedTheme) else {
                return .failure(message: "Apple Wallet couldn't verify the updated pass design.")
            }
            return .updated
        }

        // 6. Present `PKAddPassesViewController` over the topmost view
        //    controller. We resolve "topmost" through the active
        //    UIWindowScene — required since iOS 13 because there can
        //    be multiple windows in the foreground.
        guard let addVC = PKAddPassesViewController(pass: pkpass) else {
            return .failure(message: "PassKit declined the pass — likely a duplicate or wrong device.")
        }
        guard let presenter = topPresenter() else {
            return .failure(message: "Couldn't find a screen to add the pass to.")
        }
        guard activeAddPassController == nil,
              !EusoTripAPI.shared.isAppRadioSilenceEnforced else {
            return .failure(message: "Apple Wallet is unavailable while another protected flow is active.")
        }
        addVC.delegate = self
        activeAddPassController = addVC
        transportRegistration = AppRadioSilenceDirectTransportController.shared.register(
            stop: { [weak self, weak addVC] in
                addVC?.dismiss(animated: false)
                self?.finishAddPassController(addVC)
            }
        )
        presenter.present(addVC, animated: true)
        return .presented
    }

    private func finishAddPassController(_ controller: PKAddPassesViewController?) {
        if let controller, activeAddPassController !== controller { return }
        AppRadioSilenceDirectTransportController.shared.unregister(transportRegistration)
        transportRegistration = nil
        activeAddPassController = nil
    }

    private func currentThemeSelection() async throws -> ThemeSelection {
        async let themesRequest = EusoTripAPI.shared.listWalletThemes()
        async let selectedRequest = EusoTripAPI.shared.getWalletTheme()
        let (themes, selected) = try await (themesRequest, selectedRequest)
        guard let theme = themes.first(where: { $0.id == selected.themeId }),
              theme.revision == selected.themeRevision,
              theme.digest == selected.themeDigest,
              theme.manifestVersion == selected.manifestVersion,
              let revision = theme.revision else {
            throw WalletPassSelectionError.catalogMismatch
        }
        return ThemeSelection(id: theme.id, revision: revision)
    }

    private static func matches(_ pass: PKPass,
                                expectedTheme: EusoTripAPI.WalletThemeMetadata) -> Bool {
        pass.userInfo?["walletThemeId"] as? String == expectedTheme.id
            && pass.userInfo?["walletThemeRevision"] as? String == expectedTheme.revision
            && pass.userInfo?["walletThemeDigest"] as? String == expectedTheme.digest
            && pass.userInfo?["walletThemeManifestVersion"] as? String == expectedTheme.manifestVersion
            && pass.userInfo?["walletThemePassStyle"] as? String == expectedTheme.passStyle
            && pass.userInfo?["walletThemeArtSlot"] as? String == expectedTheme.artSlot
    }

    private static func hasAuthenticatedUpdateChannel(_ pass: PKPass) -> Bool {
        guard let serviceURL = pass.webServiceURL,
              serviceURL.scheme?.lowercased() == "https",
              serviceURL.user == nil,
              serviceURL.password == nil,
              serviceURL.query == nil,
              serviceURL.fragment == nil,
              let token = pass.authenticationToken,
              token.range(
                of: "^[A-Za-z0-9_-]{32,128}$",
                options: .regularExpression
              ) != nil else { return false }
        return true
    }

    static func signedPassAvailable(status: String, hasPassURL: Bool) throws -> Bool {
        switch (status, hasPassURL) {
        case ("signed", true):
            return true
        case ("not_configured", false):
            return false
        case ("signing_failed", _):
            throw WalletPassContractError(
                message: "Apple Wallet signing failed. Try again or contact support."
            )
        case ("storage_failed", _):
            throw WalletPassContractError(
                message: "The signed Wallet pass could not be stored. Try again."
            )
        case ("update_service_failed", _):
            throw WalletPassContractError(
                message: "Secure Apple Wallet updates are temporarily unavailable. Try again."
            )
        case ("signed", false):
            throw WalletPassContractError(
                message: "The credential service reported a signed Wallet pass but did not return it."
            )
        case ("not_configured", true):
            throw WalletPassContractError(
                message: "The credential service returned a Wallet pass without active signing."
            )
        default:
            throw WalletPassContractError(
                message: "The credential service returned an unsupported Wallet status."
            )
        }
    }

    private static func isThemeCatalogConflict(_ error: Error) -> Bool {
        guard case EusoTripAPIError.trpcError(let message) = error else { return false }
        return message.localizedCaseInsensitiveContains("wallet theme catalog changed")
    }

    /// Resolves the currently-active topmost UIViewController so we
    /// can present PassKit's modal over it. SwiftUI surfaces don't
    /// expose their hosting view controller directly, so we walk the
    /// window scene → window → root → presented chain.
    private func topPresenter() -> UIViewController? {
        let scene = UIApplication.shared
            .connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        let window = scene?.windows.first(where: { $0.isKeyWindow })
            ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

extension EusoWalletPassService: PKAddPassesViewControllerDelegate {
    nonisolated func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
        controller.dismiss(animated: true) {
            Task { @MainActor in
                self.finishAddPassController(controller)
            }
        }
    }
}

private enum WalletPassSelectionError: Error {
    case catalogMismatch
}

private struct WalletPassContractError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
