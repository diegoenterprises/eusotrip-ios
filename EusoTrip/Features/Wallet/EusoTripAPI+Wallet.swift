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
//  Every field is decoded defensively (optional / tolerant) so a renamed or
//  missing server field can NEVER throw a decode error and blank the surface.
//

import Foundation

extension EusoTripAPI {

    /// `{ themeId }` — current choice (getWalletTheme). `resolveTheme()` on the
    /// server guarantees a valid id, but decode tolerantly regardless.
    struct WalletThemeRef: Decodable {
        let themeId: String
        private enum CodingKeys: String, CodingKey { case themeId }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            themeId = (try? c?.decodeIfPresent(String.self, forKey: .themeId)) ?? WalletCardTheme.defaultId
        }
    }

    /// `{ ok, themeId }` — setWalletTheme result.
    struct WalletThemeSetResult: Decodable {
        let ok: Bool
        let themeId: String
        private enum CodingKeys: String, CodingKey { case ok, themeId }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            ok      = (try? c?.decodeIfPresent(Bool.self, forKey: .ok)) ?? true
            themeId = (try? c?.decodeIfPresent(String.self, forKey: .themeId)) ?? WalletCardTheme.defaultId
        }
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
        let pkpassUrl: String?     // nil when PassKit isn't configured → fall back to inline QR
        let expiresAt: String?

        private enum CodingKeys: String, CodingKey {
            case loadId, loadNumber, accessToken, shortCode, pkpassUrl, expiresAt
        }
        init(from decoder: Decoder) throws {
            let c = try? decoder.container(keyedBy: CodingKeys.self)
            loadId      = (try? c?.decodeIfPresent(String.self, forKey: .loadId)) ?? ""
            loadNumber  = (try? c?.decodeIfPresent(String.self, forKey: .loadNumber)) ?? nil
            accessToken = (try? c?.decodeIfPresent(String.self, forKey: .accessToken)) ?? ""
            shortCode   = (try? c?.decodeIfPresent(String.self, forKey: .shortCode)) ?? ""
            pkpassUrl   = (try? c?.decodeIfPresent(String.self, forKey: .pkpassUrl)) ?? nil
            expiresAt   = (try? c?.decodeIfPresent(String.self, forKey: .expiresAt)) ?? nil
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
    func setWalletTheme(_ themeId: String) async throws -> WalletThemeSetResult {
        struct In: Encodable { let themeId: String }
        return try await mutation("eusoWallet.setWalletTheme", input: In(themeId: themeId))
    }

    /// Mints a pickup credential; the server stamps the caller's chosen theme onto the pass.
    /// The server keys on a NUMERIC load id (`parseInt(loadId)`) — the caller is
    /// responsible for passing a numeric id string (see WalletCardStore).
    func createPickupCredential(loadId: String, expiresInHours: Int = 24) async throws -> PickupCredential {
        struct In: Encodable { let loadId: String; let expiresInHours: Int }
        return try await mutation("eusoWallet.createPickupCredential",
                                  input: In(loadId: loadId, expiresInHours: expiresInHours))
    }
}
