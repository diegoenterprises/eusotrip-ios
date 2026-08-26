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
//    4. If signing is explicitly not configured → return the real inline
//       credential. Download, signing, storage, and update failures surface
//       as failures rather than masquerading as successful fallback.
//
//  Powered by ESANG AI™.
//

import Foundation
import CryptoKit
import PassKit
import UIKit
import zlib

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

enum EusoWalletCredentialKind {
    case pickup
    case staffAccess

    func requiredFieldKeys(passStyle: String) -> Set<String> {
        switch self {
        case .pickup:
            let laneKeys: Set<String> = passStyle == "boardingPass"
                ? ["origin", "destination"]
                : ["lane"]
            return Set(["loadId", "eta", "shortCode", "equipment", "carrier",
                        "escrow", "token", "support"]).union(laneKeys)
        case .staffAccess:
            return ["role", "staff", "facility", "accessCode", "expires",
                    "token", "support"]
        }
    }
}

@MainActor
final class EusoWalletPassService {

    static let shared = EusoWalletPassService()
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
        let theme: WalletCardTheme
        let revision: String

        var id: String { theme.id }
    }

    struct PreparedPickupCredential {
        let credential: EusoTripAPI.PickupCredential
        let selectedTheme: WalletCardTheme
    }

    /// Mint a credential and try to add it to Apple Wallet. The tap
    /// path is end-to-end here — no view controller wiring required by
    /// the caller. Returns a `EusoWalletPassResult` so the call site
    /// can render the right UX (toast, inline fallback, error banner).
    func addPass(forLoadId loadId: String) async -> EusoWalletPassResult {
        // 0. Normalize the app's known display ids. Unknown or malformed
        //    forms remain untouched and fail the server's strict numeric-id
        //    contract instead of being lossy-converted to another load.
        let resolvedLoadId = Self.numericLoadId(from: loadId)

        // 1. Mint the credential server-side. The server signs the QR
        //    payload, generates a 5-digit shortCode, and (when the
        //    signing pipeline is healthy) uploads a .pkpass bundle to
        //    Azure Blob and returns its presigned URL.
        let prepared: PreparedPickupCredential
        do {
            prepared = try await preparePickupCredential(forLoadId: resolvedLoadId)
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
        let credential = prepared.credential
        let selectedTheme = prepared.selectedTheme

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
              Self.matches(signedTheme, selectedTheme: selectedTheme, credentialKind: .pickup),
              let manifestDigest = Self.nonEmpty(credential.manifestDigest) else {
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
            expectedVisualTheme: selectedTheme,
            expectedManifestDigest: manifestDigest,
            expectedPassTypeIdentifier: expectedPassType,
            expectedSerialNumber: expectedSerial,
            credentialKind: .pickup
        )
    }

    /// Resolve the caller's exact versioned selection and mint against that
    /// revision. A catalog rollover retries once with the refreshed selection;
    /// a signer response that substitutes another theme is rejected.
    func preparePickupCredential(forLoadId loadId: String,
                                 expiresInHours: Int = 24) async throws -> PreparedPickupCredential {
        let resolvedLoadId = Self.numericLoadId(from: loadId)
        var selection = try await currentThemeSelection()
        let credential: EusoTripAPI.PickupCredential
        do {
            credential = try await EusoTripAPI.shared.createPickupCredential(
                loadId: resolvedLoadId,
                expiresInHours: expiresInHours,
                themeId: selection.id,
                themeRevision: selection.revision
            )
        } catch {
            guard Self.isThemeCatalogConflict(error) else { throw error }
            do {
                selection = try await currentThemeSelection()
            } catch {
                throw WalletPassContractError(
                    message: "Wallet styles changed and couldn't be refreshed. Refresh styles and try again."
                )
            }
            credential = try await EusoTripAPI.shared.createPickupCredential(
                loadId: resolvedLoadId,
                expiresInHours: expiresInHours,
                themeId: selection.id,
                themeRevision: selection.revision
            )
        }

        guard Self.matches(
            credential.theme,
            selectedTheme: selection.theme,
            credentialKind: .pickup
        ) else {
            throw WalletPassContractError(
                message: "The credential service substituted a different Wallet design. Refresh styles and try again."
            )
        }
        return PreparedPickupCredential(credential: credential, selectedTheme: selection.theme)
    }

    /// Download and install an already-minted pass URL. This is shared by the
    /// wallet picker, BOL wallet screen, and document viewer so duplicate-pass
    /// replacement and download security cannot drift between entry points.
    func addPass(from url: URL,
                 expectedTheme: EusoTripAPI.WalletThemeMetadata,
                 expectedVisualTheme: WalletCardTheme,
                 expectedManifestDigest: String,
                 expectedPassTypeIdentifier: String,
                 expectedSerialNumber: String,
                 credentialKind: EusoWalletCredentialKind) async -> EusoWalletPassResult {
        // Pull through the app's bounded, auth-aware transport. It adds the
        // bearer only for EusoTrip hosts and leaves Azure SAS URLs untouched.
        let data: Data
        do {
            data = try await EusoTripAPI.shared.fetchBoundedWalletPassData(url)
        } catch {
            return .failure(message: "Couldn't download the wallet pass.")
        }

        guard Self.matches(
            expectedTheme,
            selectedTheme: expectedVisualTheme,
            credentialKind: credentialKind
        ) else {
            return .failure(message: "The signed pass did not match the selected Wallet design.")
        }

        do {
            try WalletPassBundleVerifier.verify(
                data,
                expectedTheme: expectedTheme,
                expectedVisualTheme: expectedVisualTheme,
                expectedManifestDigest: expectedManifestDigest,
                expectedPassTypeIdentifier: expectedPassTypeIdentifier,
                expectedSerialNumber: expectedSerialNumber,
                credentialKind: credentialKind
            )
        } catch let error as WalletPassBundleError {
            return .failure(message: error.userMessage)
        } catch {
            return .failure(message: "The signed Wallet pass package could not be verified.")
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
        presenter.present(addVC, animated: true)
        return .presented
    }

    private func currentThemeSelection() async throws -> ThemeSelection {
        async let themesRequest = EusoTripAPI.shared.listWalletThemes()
        async let selectedRequest = EusoTripAPI.shared.getWalletTheme()
        let (themes, selected) = try await (themesRequest, selectedRequest)
        guard let theme = themes.first(where: { $0.id == selected.themeId }),
              theme.revision == selected.themeRevision,
              theme.digest == selected.themeDigest,
              theme.manifestVersion == selected.manifestVersion,
              let revision = theme.revision,
              theme.isVersioned else {
            throw WalletPassSelectionError.catalogMismatch
        }
        return ThemeSelection(theme: theme, revision: revision)
    }

    private static func matches(_ metadata: EusoTripAPI.WalletThemeMetadata,
                                selectedTheme: WalletCardTheme,
                                credentialKind: EusoWalletCredentialKind) -> Bool {
        let expectedPassStyle = credentialKind == .staffAccess
            ? "eventTicket"
            : selectedTheme.passStyle
        return metadata.id == selectedTheme.id
            && metadata.revision == selectedTheme.revision
            && metadata.digest == selectedTheme.digest
            && metadata.manifestVersion == selectedTheme.manifestVersion
            && metadata.passStyle == expectedPassStyle
            && metadata.artSlot?.nilIfBlank?.lowercased() == selectedTheme.normalizedArtSlot
    }

    private static func matches(_ pass: PKPass,
                                expectedTheme: EusoTripAPI.WalletThemeMetadata) -> Bool {
        pass.userInfo?["walletThemeId"] as? String == expectedTheme.id
            && pass.userInfo?["walletThemeRevision"] as? String == expectedTheme.revision
            && pass.userInfo?["walletThemeDigest"] as? String == expectedTheme.digest
            && pass.userInfo?["walletThemeManifestVersion"] as? String == expectedTheme.manifestVersion
            && pass.userInfo?["walletThemePassStyle"] as? String == expectedTheme.passStyle
            && (pass.userInfo?["walletThemeArtSlot"] as? String)?.nilIfBlank?.lowercased()
                == expectedTheme.artSlot?.nilIfBlank?.lowercased()
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

    private static func nonEmpty(_ value: String?) -> String? {
        value?.nilIfBlank
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

private enum WalletPassBundleError: Error {
    case malformedPackage
    case manifestMismatch
    case visualMismatch

    var userMessage: String {
        switch self {
        case .malformedPackage:
            return "The signed Wallet pass package is malformed and was not added."
        case .manifestMismatch:
            return "The downloaded Wallet pass did not match the signed package and was not added."
        case .visualMismatch:
            return "The signed Wallet pass artwork or fields did not match your selected design and were not added."
        }
    }
}

/// PassKit verifies Apple's signature. This verifier additionally proves that
/// the signed archive is the exact visual contract selected in EusoWallet:
/// manifest digest, pass style, colors, fields, QR, and canonical art bytes.
private enum WalletPassBundleVerifier {
    private static let passStyleKeys = [
        "boardingPass", "coupon", "eventTicket", "generic", "storeCard",
    ]
    private static let fieldSections = [
        "headerFields", "primaryFields", "secondaryFields", "auxiliaryFields", "backFields",
    ]
    private static let artSlots = ["background", "strip", "thumbnail"]

    static func verify(_ bundleData: Data,
                       expectedTheme: EusoTripAPI.WalletThemeMetadata,
                       expectedVisualTheme: WalletCardTheme,
                       expectedManifestDigest: String,
                       expectedPassTypeIdentifier: String,
                       expectedSerialNumber: String,
                       credentialKind: EusoWalletCredentialKind) throws {
        let archive = try WalletZipArchive(data: bundleData)
        guard let passData = archive.files["pass.json"],
              let manifestData = archive.files["manifest.json"],
              archive.files["signature"] != nil else {
            throw WalletPassBundleError.malformedPackage
        }

        guard digest(expectedManifestDigest, matches: manifestData) else {
            throw WalletPassBundleError.manifestMismatch
        }
        try verifyManifest(manifestData, archive: archive)
        try verifyPassJSON(
            passData,
            archive: archive,
            expectedTheme: expectedTheme,
            expectedVisualTheme: expectedVisualTheme,
            expectedPassTypeIdentifier: expectedPassTypeIdentifier,
            expectedSerialNumber: expectedSerialNumber,
            credentialKind: credentialKind
        )
    }

    private static func verifyManifest(_ manifestData: Data,
                                       archive: WalletZipArchive) throws {
        let object = try? JSONSerialization.jsonObject(with: manifestData)
        guard let manifest = object as? [String: String] else {
            throw WalletPassBundleError.malformedPackage
        }

        let signedFiles = Set(archive.files.keys).subtracting(["manifest.json", "signature"])
        guard Set(manifest.keys) == signedFiles else {
            throw WalletPassBundleError.manifestMismatch
        }
        for (name, expectedHash) in manifest {
            guard let bytes = archive.files[name],
                  sha1Hex(bytes) == expectedHash.lowercased() else {
                throw WalletPassBundleError.manifestMismatch
            }
        }
    }

    private static func verifyPassJSON(_ passData: Data,
                                       archive: WalletZipArchive,
                                       expectedTheme: EusoTripAPI.WalletThemeMetadata,
                                       expectedVisualTheme: WalletCardTheme,
                                       expectedPassTypeIdentifier: String,
                                       expectedSerialNumber: String,
                                       credentialKind: EusoWalletCredentialKind) throws {
        let object = try? JSONSerialization.jsonObject(with: passData)
        guard let pass = object as? [String: Any],
              string(pass["passTypeIdentifier"]) == expectedPassTypeIdentifier.nilIfBlank,
              string(pass["serialNumber"]) == expectedSerialNumber.nilIfBlank,
              canonicalColor(string(pass["backgroundColor"])) == canonicalColor(expectedVisualTheme.background),
              canonicalColor(string(pass["foregroundColor"])) == canonicalColor(expectedVisualTheme.foreground),
              canonicalColor(string(pass["labelColor"])) == canonicalColor(expectedVisualTheme.label) else {
            throw WalletPassBundleError.visualMismatch
        }

        let presentStyles = passStyleKeys.filter { pass[$0] != nil }
        guard presentStyles == [expectedTheme.passStyle],
              let fields = pass[expectedTheme.passStyle] as? [String: Any] else {
            throw WalletPassBundleError.visualMismatch
        }

        var fieldKeys = Set<String>()
        for section in fieldSections {
            guard let rows = fields[section] else { continue }
            guard let values = rows as? [[String: Any]] else {
                throw WalletPassBundleError.visualMismatch
            }
            for value in values {
                guard let key = string(value["key"]), !key.isEmpty else {
                    throw WalletPassBundleError.visualMismatch
                }
                fieldKeys.insert(key)
            }
        }
        guard credentialKind.requiredFieldKeys(passStyle: expectedTheme.passStyle)
                .isSubset(of: fieldKeys),
              hasQRBarcode(pass) else {
            throw WalletPassBundleError.visualMismatch
        }

        switch (credentialKind, expectedTheme.passStyle) {
        case (.pickup, "boardingPass"):
            guard string(fields["transitType"]) == "PKTransitTypeGeneric" else {
                throw WalletPassBundleError.visualMismatch
            }
        case (.pickup, "eventTicket"), (.staffAccess, "eventTicket"):
            guard fields["transitType"] == nil else {
                throw WalletPassBundleError.visualMismatch
            }
        default:
            throw WalletPassBundleError.visualMismatch
        }

        guard let userInfo = pass["userInfo"] as? [String: Any],
              string(userInfo["walletThemeId"]) == expectedTheme.id,
              string(userInfo["walletThemeRevision"]) == expectedTheme.revision,
              string(userInfo["walletThemeDigest"]) == expectedTheme.digest,
              string(userInfo["walletThemeManifestVersion"]) == expectedTheme.manifestVersion,
              string(userInfo["walletThemePassStyle"]) == expectedTheme.passStyle,
              string(userInfo["walletThemeArtSlot"])?.nilIfBlank?.lowercased()
                == expectedTheme.artSlot?.nilIfBlank?.lowercased() else {
            throw WalletPassBundleError.visualMismatch
        }

        let expectedSlot = expectedTheme.artSlot?.nilIfBlank?.lowercased()
        guard expectedSlot == expectedVisualTheme.normalizedArtSlot else {
            throw WalletPassBundleError.visualMismatch
        }
        if let expectedSlot {
            guard artSlots.contains(expectedSlot),
                  let expectedHashes = expectedVisualTheme.expectedPassArtworkSHA256,
                  expectedHashes.count == 3 else {
                throw WalletPassBundleError.visualMismatch
            }
            for (index, suffix) in [".png", "@2x.png", "@3x.png"].enumerated() {
                guard let art = archive.files[expectedSlot + suffix],
                      art.count > 100,
                      art.starts(with: [0x89, 0x50, 0x4e, 0x47]),
                      sha256Hex(art) == expectedHashes[index] else {
                    throw WalletPassBundleError.visualMismatch
                }
            }
        } else {
            let unexpectedArt = archive.files.keys.contains { name in
                artSlots.contains { slot in
                    name == "\(slot).png" || name == "\(slot)@2x.png" || name == "\(slot)@3x.png"
                }
            }
            guard !unexpectedArt else { throw WalletPassBundleError.visualMismatch }
        }
    }

    private static func hasQRBarcode(_ pass: [String: Any]) -> Bool {
        let values: [[String: Any]]
        if let barcodes = pass["barcodes"] as? [[String: Any]] {
            values = barcodes
        } else if let barcode = pass["barcode"] as? [String: Any] {
            values = [barcode]
        } else {
            return false
        }
        return values.contains { barcode in
            string(barcode["format"]) == "PKBarcodeFormatQR"
                && !(string(barcode["message"])?.isEmpty ?? true)
        }
    }

    private static func digest(_ reported: String, matches data: Data) -> Bool {
        let value = reported.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("sha256:") {
            return String(value.dropFirst(7)) == sha256Hex(data)
        }
        if value.hasPrefix("sha1:") {
            return String(value.dropFirst(5)) == sha1Hex(data)
        }
        switch value.count {
        case 64: return value == sha256Hex(data)
        case 40: return value == sha1Hex(data)
        default: return false
        }
    }

    private static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func string(_ value: Any?) -> String? {
        (value as? String)?.nilIfBlank
    }

    private static func canonicalColor(_ value: String?) -> String? {
        value?.lowercased().filter { !$0.isWhitespace }
    }
}

/// Minimal bounded ZIP reader for a PassKit bundle. It rejects encryption,
/// Zip64, path traversal, duplicate names, unsupported compression, and
/// oversized expansion before any pass content is trusted.
private struct WalletZipArchive {
    let files: [String: Data]

    init(data: Data) throws {
        guard data.count >= 22,
              let eocd = Self.endOfCentralDirectory(in: data) else {
            throw WalletPassBundleError.malformedPackage
        }

        let disk = try data.walletUInt16(at: eocd + 4)
        let centralDisk = try data.walletUInt16(at: eocd + 6)
        let diskEntries = try data.walletUInt16(at: eocd + 8)
        let totalEntries = try data.walletUInt16(at: eocd + 10)
        let centralSize32 = try data.walletUInt32(at: eocd + 12)
        let centralOffset32 = try data.walletUInt32(at: eocd + 16)
        let commentLength = Int(try data.walletUInt16(at: eocd + 20))

        guard disk == 0, centralDisk == 0, diskEntries == totalEntries,
              totalEntries <= 128,
              centralSize32 != UInt32.max,
              centralOffset32 != UInt32.max,
              eocd + 22 + commentLength == data.count else {
            throw WalletPassBundleError.malformedPackage
        }

        let centralOffset = Int(centralOffset32)
        let centralSize = Int(centralSize32)
        guard centralOffset >= 0, centralSize >= 0,
              centralOffset + centralSize <= eocd else {
            throw WalletPassBundleError.malformedPackage
        }

        var cursor = centralOffset
        var decoded: [String: Data] = [:]
        var expandedBytes = 0
        for _ in 0..<Int(totalEntries) {
            guard try data.walletUInt32(at: cursor) == 0x02014b50 else {
                throw WalletPassBundleError.malformedPackage
            }
            let flags = try data.walletUInt16(at: cursor + 8)
            let method = try data.walletUInt16(at: cursor + 10)
            let checksum = try data.walletUInt32(at: cursor + 16)
            let compressedSize32 = try data.walletUInt32(at: cursor + 20)
            let uncompressedSize32 = try data.walletUInt32(at: cursor + 24)
            let nameLength = Int(try data.walletUInt16(at: cursor + 28))
            let extraLength = Int(try data.walletUInt16(at: cursor + 30))
            let entryCommentLength = Int(try data.walletUInt16(at: cursor + 32))
            let entryDisk = try data.walletUInt16(at: cursor + 34)
            let localOffset32 = try data.walletUInt32(at: cursor + 42)

            guard flags & 0x0001 == 0,
                  method == 0 || method == 8,
                  entryDisk == 0,
                  compressedSize32 != UInt32.max,
                  uncompressedSize32 != UInt32.max,
                  localOffset32 != UInt32.max else {
                throw WalletPassBundleError.malformedPackage
            }

            let nameStart = cursor + 46
            let nextCursor = nameStart + nameLength + extraLength + entryCommentLength
            guard nameLength > 0, nextCursor <= centralOffset + centralSize,
                  let name = String(data: try data.walletSlice(nameStart..<(nameStart + nameLength)),
                                    encoding: .utf8),
                  Self.isSafe(name: name),
                  decoded[name] == nil else {
                throw WalletPassBundleError.malformedPackage
            }

            let compressedSize = Int(compressedSize32)
            let uncompressedSize = Int(uncompressedSize32)
            expandedBytes += uncompressedSize
            guard compressedSize <= 12 * 1_024 * 1_024,
                  uncompressedSize <= 12 * 1_024 * 1_024,
                  expandedBytes <= 24 * 1_024 * 1_024 else {
                throw WalletPassBundleError.malformedPackage
            }

            let localOffset = Int(localOffset32)
            guard try data.walletUInt32(at: localOffset) == 0x04034b50,
                  try data.walletUInt16(at: localOffset + 8) == method else {
                throw WalletPassBundleError.malformedPackage
            }
            let localNameLength = Int(try data.walletUInt16(at: localOffset + 26))
            let localExtraLength = Int(try data.walletUInt16(at: localOffset + 28))
            let localNameStart = localOffset + 30
            let localNameData = try data.walletSlice(localNameStart..<(localNameStart + localNameLength))
            guard String(data: localNameData, encoding: .utf8) == name else {
                throw WalletPassBundleError.malformedPackage
            }
            let bytesStart = localNameStart + localNameLength + localExtraLength
            let bytesEnd = bytesStart + compressedSize
            guard bytesStart >= 0, bytesEnd <= centralOffset else {
                throw WalletPassBundleError.malformedPackage
            }
            let compressed = try data.walletSlice(bytesStart..<bytesEnd)
            let contents: Data
            if method == 0 {
                guard compressed.count == uncompressedSize else {
                    throw WalletPassBundleError.malformedPackage
                }
                contents = compressed
            } else {
                contents = try Self.inflateRaw(compressed, expectedSize: uncompressedSize)
            }
            guard Self.crc32(contents) == checksum else {
                throw WalletPassBundleError.malformedPackage
            }
            decoded[name] = contents
            cursor = nextCursor
        }

        guard cursor == centralOffset + centralSize,
              decoded.count == Int(totalEntries) else {
            throw WalletPassBundleError.malformedPackage
        }
        files = decoded
    }

    private static func endOfCentralDirectory(in data: Data) -> Int? {
        let lowerBound = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= lowerBound {
            if (try? data.walletUInt32(at: offset)) == 0x06054b50 { return offset }
            if offset == lowerBound { break }
            offset -= 1
        }
        return nil
    }

    private static func isSafe(name: String) -> Bool {
        guard !name.hasPrefix("/"), !name.hasPrefix("\\"), !name.contains("\0") else {
            return false
        }
        return !name.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
            .contains("..")
    }

    private static func inflateRaw(_ compressed: Data,
                                   expectedSize: Int) throws -> Data {
        var output = Data(count: max(1, expectedSize))
        let outputCapacity = output.count
        var stream = z_stream()
        let result: Int32 = compressed.withUnsafeBytes { sourceBuffer in
            output.withUnsafeMutableBytes { destinationBuffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(
                    mutating: sourceBuffer.bindMemory(to: Bytef.self).baseAddress
                )
                stream.avail_in = uInt(compressed.count)
                stream.next_out = destinationBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCapacity)
                guard inflateInit2_(
                    &stream,
                    -MAX_WBITS,
                    ZLIB_VERSION,
                    Int32(MemoryLayout<z_stream>.size)
                ) == Z_OK else { return Z_STREAM_ERROR }
                defer { inflateEnd(&stream) }
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END,
              Int(stream.total_out) == expectedSize else {
            throw WalletPassBundleError.malformedPackage
        }
        output.count = expectedSize
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        let value: uLong = data.withUnsafeBytes { buffer in
            zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))
        }
        return UInt32(truncatingIfNeeded: value)
    }
}

private extension Data {
    func walletUInt16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else {
            throw WalletPassBundleError.malformedPackage
        }
        return withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let low = UInt16(bytes[offset])
            let high = UInt16(bytes[offset + 1]) << 8
            return low | high
        }
    }

    func walletUInt32(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= count else {
            throw WalletPassBundleError.malformedPackage
        }
        return withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let byte0 = UInt32(bytes[offset])
            let byte1 = UInt32(bytes[offset + 1]) << 8
            let byte2 = UInt32(bytes[offset + 2]) << 16
            let byte3 = UInt32(bytes[offset + 3]) << 24
            return byte0 | byte1 | byte2 | byte3
        }
    }

    func walletSlice(_ range: Range<Int>) throws -> Data {
        guard range.lowerBound >= 0,
              range.upperBound >= range.lowerBound,
              range.upperBound <= count else {
            throw WalletPassBundleError.malformedPackage
        }
        return subdata(in: range)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private enum WalletPassSelectionError: Error {
    case catalogMismatch
}

private struct WalletPassContractError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
