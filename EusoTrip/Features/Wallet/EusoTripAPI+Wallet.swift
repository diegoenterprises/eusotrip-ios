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

private final class WalletPassNoRedirectDelegate: NSObject,
                                                   URLSessionTaskDelegate,
                                                   @unchecked Sendable {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

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
        let passTypeIdentifier: String?
        let passSerialNumber: String?
        let expiresAt: String

        private enum CodingKeys: String, CodingKey {
            case loadId, loadNumber, accessToken, shortCode, pkpassUrl, passkitStatus
            case theme, signedTheme, manifestDigest, passTypeIdentifier, passSerialNumber
            case expiresAt
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
            passTypeIdentifier = try c.decodeIfPresent(String.self, forKey: .passTypeIdentifier)
            passSerialNumber = try c.decodeIfPresent(String.self, forKey: .passSerialNumber)
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
    /// The server accepts only a positive numeric database id; display-id
    /// normalization is centralized in EusoWalletPassService.
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

    /// Fetch a signed `.pkpass` under a hard streaming byte ceiling. The
    /// generic API transport materializes `Data` before it can inspect size;
    /// Wallet bundles use this path so a chunked or dishonest response cannot
    /// consume unbounded memory. Redirects are rejected, and the bearer is
    /// attached only to the exact configured EusoTrip origin.
    func fetchBoundedWalletPassData(_ url: URL,
                                    maxBytes: Int = 12 * 1_024 * 1_024) async throws -> Data {
        guard maxBytes > 0,
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              let requestedHost = url.host?.lowercased() else {
            throw EusoTripAPIError.badURL
        }

        let isFirstParty: Bool
        if let baseURL,
           let baseScheme = baseURL.scheme?.lowercased(),
           let baseHost = baseURL.host?.lowercased() {
            let basePort = baseURL.port ?? (baseScheme == "https" ? 443 : 80)
            let requestPort = url.port ?? 443
            isFirstParty = baseScheme == "https"
                && baseHost == requestedHost
                && basePort == requestPort
        } else {
            isFirstParty = false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.apple.pkpass", forHTTPHeaderField: "Accept")
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        if isFirstParty, let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 22
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(
            configuration: configuration,
            delegate: WalletPassNoRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EusoTripAPIError.httpStatus(0, "No HTTP response")
        }
        guard let finalURL = http.url,
              finalURL.scheme?.lowercased() == "https",
              finalURL.host?.lowercased() == requestedHost else {
            throw EusoTripAPIError.badURL
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EusoTripAPIError.httpStatus(http.statusCode, "Wallet pass download failed")
        }
        guard http.mimeType?.lowercased() == "application/vnd.apple.pkpass" else {
            throw EusoTripAPIError.httpStatus(
                http.statusCode,
                "Unexpected Wallet pass content type"
            )
        }
        if http.expectedContentLength > Int64(maxBytes) {
            throw EusoTripAPIError.httpStatus(http.statusCode, "Wallet pass size is invalid")
        }

        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(http.expectedContentLength), maxBytes))
        }
        for try await byte in stream {
            guard data.count < maxBytes else {
                throw EusoTripAPIError.httpStatus(http.statusCode, "Wallet pass size is invalid")
            }
            data.append(byte)
        }
        guard !data.isEmpty else {
            throw EusoTripAPIError.httpStatus(http.statusCode, "Wallet pass size is invalid")
        }
        return data
    }
}
