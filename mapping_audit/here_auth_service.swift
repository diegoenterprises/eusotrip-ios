//
//  HEREAuthService.swift
//  EusoTrip — OAuth 2.0 client-credentials (OAuth1.0a-signed) token manager
//  for the HERE Platform.
//
//  PROPOSAL — NOT YET LINKED INTO THE APP TARGET.
//  This file lives in `mapping_audit/` for review. Once approved, move to
//  `EusoTrip/Services/HereMaps/HEREAuthService.swift` and add to the Xcode
//  `Sources` build phase alongside the other HereMaps files.
//
//  HERE's "app credentials" flow:
//    1. POST https://account.api.here.com/oauth2/token
//       with OAuth1.0a HMAC-SHA256 signature in the Authorization header.
//    2. Body: `grant_type=client_credentials`.
//    3. Response: `{ access_token, token_type: "bearer", expires_in: 86399 }`.
//    4. Use `Authorization: Bearer <access_token>` on every subsequent
//       HERE REST API call. Token lifetime is ~24 h — we refresh 30 min
//       before expiry.
//
//  Powered by ESANG AI™.
//

import Foundation
import CryptoKit
import Security

/// Actor-isolated manager for a single cached HERE OAuth bearer token.
/// All entry points are async; callers should `await HEREAuthService.shared.currentToken()`.
actor HEREAuthService {

    // MARK: - Public

    static let shared = HEREAuthService()

    /// Returns a valid (unexpired) Bearer token. Reuses the in-memory cache
    /// if possible; falls through to Keychain-persisted cache; otherwise
    /// exchanges credentials for a fresh token. Concurrent callers coalesce
    /// onto the same in-flight `Task`.
    func currentToken() async throws -> String {
        if let cached = cached, cached.isFresh {
            return cached.token
        }

        if let disk = loadFromKeychain(), disk.isFresh {
            self.cached = disk
            schedulePrefetchIfNeeded(for: disk)
            return disk.token
        }

        if let inFlight = refreshTask {
            return try await inFlight.value
        }

        let task = Task { try await self.exchange() }
        refreshTask = task
        defer { refreshTask = nil }

        let fresh = try await task.value
        self.cached = fresh
        saveToKeychain(fresh)
        schedulePrefetchIfNeeded(for: fresh)
        return fresh.token
    }

    /// Drops every cached token (memory + Keychain). Call on HTTP 401 from
    /// a downstream HERE API so the next `currentToken()` call re-exchanges.
    func invalidate() {
        cached = nil
        deleteFromKeychain()
        refreshTask?.cancel()
        refreshTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    // MARK: - Internal cached-token type

    struct CachedToken: Codable, Equatable {
        let token: String
        let expiresAt: Date

        /// Still has >30 min of life left.
        var isFresh: Bool { expiresAt.timeIntervalSinceNow > 30 * 60 }
        /// Hit the refresh window (<=30 min of life).
        var needsRefresh: Bool { !isFresh }
    }

    // MARK: - Private state

    private var cached: CachedToken?
    private var refreshTask: Task<CachedToken, Error>?
    private var prefetchTask: Task<Void, Never>?

    private let session: URLSession
    private let decoder: JSONDecoder

    private init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Exchange

    /// Performs a fresh OAuth1.0a-signed POST to `/oauth2/token` and returns
    /// the resulting CachedToken. Throws `HereMapsError.*` on failure.
    private func exchange() async throws -> CachedToken {
        guard
            let keyId      = HereMapsConfig.accessKeyId,
            let keySecret  = HereMapsConfig.accessKeySecret,
            let tokenURL   = HereMapsConfig.tokenEndpointURL
        else {
            throw HereMapsError.missingAPIKey
        }

        let method    = "POST"
        let baseURL   = tokenURL.absoluteString
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let nonce     = Self.randomNonce()

        // OAuth1.0a signing parameters. `grant_type` is a body param that
        // MUST participate in the signature base string.
        let oauthParams: [(String, String)] = [
            ("grant_type",              "client_credentials"),
            ("oauth_consumer_key",      keyId),
            ("oauth_nonce",             nonce),
            ("oauth_signature_method",  "HMAC-SHA256"),
            ("oauth_timestamp",         timestamp),
            ("oauth_version",           "1.0"),
        ]

        let signature = Self.sign(
            method:     method,
            url:        baseURL,
            params:     oauthParams,
            keySecret:  keySecret
        )

        // Authorization header — note: `grant_type` does NOT go in the
        // header, only body params that are OAuth-prefixed do. We include
        // oauth_* only here. The signature we computed used both, which is
        // correct per the OAuth1.0a base-string spec.
        let headerParams: [(String, String)] = [
            ("oauth_consumer_key",      keyId),
            ("oauth_nonce",             nonce),
            ("oauth_signature_method",  "HMAC-SHA256"),
            ("oauth_timestamp",         timestamp),
            ("oauth_version",           "1.0"),
            ("oauth_signature",         signature),
        ]
        let authHeader = "OAuth " + headerParams
            .map { "\($0.0)=\"\(Self.percentEncode($0.1))\"" }
            .joined(separator: ",")

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("grant_type=client_credentials".utf8)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw HereMapsError.providerError("No HTTP response from HERE OAuth")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HereMapsError.http(http.statusCode, "HERE OAuth: \(body)")
        }

        let payload: TokenResponse
        do {
            payload = try decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw HereMapsError.decoding("HERE OAuth response: \(error)")
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(payload.expires_in))
        return CachedToken(token: payload.access_token, expiresAt: expiresAt)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let expires_in: Int
    }

    // MARK: - Background prefetch

    /// Schedules a single background refresh so the token is renewed just
    /// before it expires. Safe to call repeatedly — only one prefetch task
    /// is alive at a time.
    private func schedulePrefetchIfNeeded(for cached: CachedToken) {
        prefetchTask?.cancel()
        let lead: TimeInterval = 30 * 60        // 30 min before expiry
        let fireIn = cached.expiresAt.timeIntervalSinceNow - lead
        guard fireIn > 0 else { return }

        prefetchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(fireIn * 1_000_000_000))
            guard let self = self else { return }
            _ = try? await self.currentToken()
        }
    }

    // MARK: - Keychain persistence

    private static let keychainService = "com.eusorone.eusotrip.hereoauth"
    private static let keychainAccount = "bearer"

    private func saveToKeychain(_ token: CachedToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Self.keychainService,
            kSecAttrAccount as String:      Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String]       = data
        add[kSecAttrAccessible as String]  = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadFromKeychain() -> CachedToken? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      Self.keychainService,
            kSecAttrAccount as String:      Self.keychainAccount,
            kSecReturnData as String:       kCFBooleanTrue as Any,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let decoded = try? JSONDecoder().decode(CachedToken.self, from: data)
        else { return nil }
        return decoded
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  Self.keychainService,
            kSecAttrAccount as String:  Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - OAuth1.0a helpers

    /// Computes the OAuth1.0a HMAC-SHA256 signature for a HERE token-exchange
    /// request. Caller must pre-compute the base URL (no query string) and
    /// pass every signed parameter — the body `grant_type` plus every
    /// `oauth_*` field except `oauth_signature` itself.
    static func sign(method: String,
                     url: String,
                     params: [(String, String)],
                     keySecret: String) -> String {
        // Alpha-sort by key (then value) after percent-encoding each part.
        let encoded = params
            .map { (percentEncode($0.0), percentEncode($0.1)) }
            .sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }
        let paramString = encoded
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")

        let baseString = [
            method.uppercased(),
            percentEncode(url),
            percentEncode(paramString),
        ].joined(separator: "&")

        // Signing key: percentEncode(consumerSecret) + "&" + percentEncode(tokenSecret).
        // For client-credentials there is no token secret, but the trailing "&" is required.
        let signingKey = percentEncode(keySecret) + "&"

        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(baseString.utf8),
            using: SymmetricKey(data: Data(signingKey.utf8))
        )
        return Data(mac).base64EncodedString()
    }

    /// RFC3986 percent-encoding — the OAuth1.0a spec requires this exact
    /// reserved-character set, which is *stricter* than URLComponents'
    /// default. Every byte outside `A-Z a-z 0-9 - . _ ~` is encoded.
    static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// 32-hex-character random nonce.
    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - HereMapsConfig additions (sketch — apply in HereMapsConfig.swift)
//
// extension HereMapsConfig {
//
//     // Info.plist keys (populated from xcconfig)
//     static let accessKeyIdPlistKey     = "HEREAccessKeyId"
//     static let accessKeySecretPlistKey = "HEREAccessKeySecret"
//     static let tokenURLPlistKey        = "HERETokenURL"
//     static let clientIdPlistKey        = "HEREClientId"
//     static let userIdPlistKey          = "HEREUserId"
//
//     static var accessKeyId: String?     { plistString(accessKeyIdPlistKey) }
//     static var accessKeySecret: String? { plistString(accessKeySecretPlistKey) }
//     static var clientId: String?        { plistString(clientIdPlistKey) }
//     static var userId: String?          { plistString(userIdPlistKey) }
//
//     static var tokenEndpointURL: URL? {
//         guard let raw = plistString(tokenURLPlistKey), let url = URL(string: raw) else {
//             return URL(string: "https://account.api.here.com/oauth2/token")
//         }
//         return url
//     }
//
//     /// Wraps HEREAuthService — call this from every REST client instead of `requireAPIKey()`.
//     static func requireBearerToken() async throws -> String {
//         try await HEREAuthService.shared.currentToken()
//     }
//
//     private static func plistString(_ key: String) -> String? {
//         guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
//               !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
//         return raw
//     }
// }
