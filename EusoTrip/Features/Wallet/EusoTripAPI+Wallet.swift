//
//  EusoTripAPI+Wallet.swift
//  EusoTrip — the tRPC bindings for the Wallet card picker.
//
//  BINDINGS ADAPTED to the REAL EusoTripAPI surface (Services/EusoTripAPI.swift):
//   • A NO-INPUT tRPC query uses `queryNoInput("router.proc")` — the generic
//     `query(_:input:)` requires an Encodable input, so the two read procs here
//     (listWalletThemes / getWalletTheme) call `queryNoInput`, matching the
//     idiom used across the app (e.g. WalletHome's `eusoWallet.getSnapshot`).
//   • Mutations use `mutation("router.proc", input:)` with a local `Encodable`.
//   • `EusoTripAPI.shared.perform(...)` unwraps the tRPC `{result:{data:{json}}}`
//     envelope, so every Decodable below decodes the INNER payload directly.
//
//  DECODE SHAPES verified against the LIVE server return shapes
//  (server/routers/eusoWallet.ts):
//   • listWalletThemes → array of { id, name, kind, background, foreground,
//                                    label, shipNow } (see WalletCardTheme).
//   • getWalletTheme   → { themeId }.
//   • setWalletTheme   → { ok, themeId }.
//   • createPickupCredential → { loadId, loadNumber, accessToken, shortCode,
//                                pkpassUrl (null until PassKit configured),
//                                expiresAt }.
//  Required credential and theme fields decode strictly so a contract drift
//  cannot be mistaken for a successful empty credential.
//

import Foundation

extension EusoTripAPI {

    /// `{ themeId }` — current choice (getWalletTheme). `resolveTheme()` on the
    /// server guarantees a valid id.
    struct WalletThemeRef: Decodable {
        let themeId: String
        let themeRevision: String
        let themeDigest: String
        let manifestVersion: String
        private enum CodingKeys: String, CodingKey {
            case themeId, themeRevision, themeDigest, manifestVersion
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            themeId = try c.decode(String.self, forKey: .themeId)
            themeRevision = try c.decode(String.self, forKey: .themeRevision)
            themeDigest = try c.decode(String.self, forKey: .themeDigest)
            manifestVersion = try c.decode(String.self, forKey: .manifestVersion)
        }
    }

    /// `{ ok, themeId }` — setWalletTheme result.
    struct WalletThemeSetResult: Decodable {
        let ok: Bool
        let themeId: String
        let themeRevision: String
        let themeDigest: String
        let manifestVersion: String
        private enum CodingKeys: String, CodingKey {
            case ok, themeId, themeRevision, themeDigest, manifestVersion
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ok      = try c.decode(Bool.self, forKey: .ok)
            themeId = try c.decode(String.self, forKey: .themeId)
            themeRevision = try c.decode(String.self, forKey: .themeRevision)
            themeDigest = try c.decode(String.self, forKey: .themeDigest)
            manifestVersion = try c.decode(String.self, forKey: .manifestVersion)
        }
    }

    struct WalletThemeMetadata: Decodable, Equatable, Hashable {
        let id: String
        let revision: String
        let digest: String
        let manifestVersion: String
        let passStyle: String
        let artSlot: String?
    }

    /// What `createPickupCredential` returns (server eusoWallet.ts ≈ line 610).
    /// Field optionality mirrors the proven EusoWalletPassService.PickupCredential:
    /// `loadNumber` and `pkpassUrl` are optional (pkpassUrl is null until the
    /// PassKit signing pipeline is configured → iOS falls back to inline QR).
    struct PickupCredential: Decodable {
        let loadId: String
        let loadNumber: String?
        let accessToken: String
        let shortCode: String
        let pkpassUrl: String?
        let passkitStatus: String
        let theme: WalletThemeMetadata
        let signedTheme: WalletThemeMetadata?
        let manifestDigest: String?
        let expiresAt: String

        private enum CodingKeys: String, CodingKey {
            case loadId, loadNumber, accessToken, shortCode, pkpassUrl, passkitStatus
            case theme, signedTheme, manifestDigest, expiresAt
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            loadId      = try c.decode(String.self, forKey: .loadId)
            loadNumber  = try c.decodeIfPresent(String.self, forKey: .loadNumber)
            accessToken = try c.decode(String.self, forKey: .accessToken)
            shortCode   = try c.decode(String.self, forKey: .shortCode)
            pkpassUrl   = try c.decodeIfPresent(String.self, forKey: .pkpassUrl)
            passkitStatus = try c.decode(String.self, forKey: .passkitStatus)
            theme = try c.decode(WalletThemeMetadata.self, forKey: .theme)
            signedTheme = try c.decodeIfPresent(WalletThemeMetadata.self, forKey: .signedTheme)
            manifestDigest = try c.decodeIfPresent(String.self, forKey: .manifestDigest)
            expiresAt = try c.decode(String.self, forKey: .expiresAt)
        }
    }

    // The 15 styles (server is the source of truth; client mirrors it).
    // NO-INPUT query → queryNoInput.
    func listWalletThemes() async throws -> [WalletCardTheme] {
        try await queryNoInput("eusoWallet.listWalletThemes")
    }

    // NO-INPUT query → queryNoInput.
    func getWalletTheme() async throws -> WalletThemeRef {
        try await queryNoInput("eusoWallet.getWalletTheme")
    }

    @discardableResult
    func setWalletTheme(_ themeId: String, revision: String) async throws -> WalletThemeSetResult {
        struct In: Encodable { let themeId: String; let themeRevision: String }
        return try await mutation(
            "eusoWallet.setWalletTheme",
            input: In(themeId: themeId, themeRevision: revision)
        )
    }

    /// Mints a pickup credential; the server stamps the caller's chosen theme onto the pass.
    /// The server keys on a NUMERIC load id (`parseInt(loadId)`) — the caller is
    /// responsible for passing a numeric id string (see WalletCardStore).
    func createPickupCredential(loadId: String,
                                expiresInHours: Int = 24,
                                themeId: String? = nil,
                                themeRevision: String? = nil) async throws -> PickupCredential {
        struct In: Encodable {
            let loadId: String
            let expiresInHours: Int
            let themeId: String?
            let themeRevision: String?
        }
        return try await mutation("eusoWallet.createPickupCredential",
                                  input: In(loadId: loadId,
                                            expiresInHours: expiresInHours,
                                            themeId: themeId,
                                            themeRevision: themeRevision))
    }
}
