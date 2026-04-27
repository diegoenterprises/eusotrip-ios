//
//  HereMapsConfig.swift
//  EusoTrip — Central config for HERE Maps Platform integration
//
//  REST APIs (Routing v8, Matrix v8, Geocoding v7, Tile v3, Isoline v8,
//  Traffic v7) authenticate via OAuth 2.0 client-credentials — a Bearer
//  token exchanged from an OAuth1.0a-HMAC-SHA256 signed request to
//  HERE's `/oauth2/token` endpoint. See `HEREAuthService.swift`.
//
//  Xcconfig (e.g. `EusoTrip.xcconfig`, git-ignored):
//      HERE_ACCESS_KEY_ID      = ...
//      HERE_ACCESS_KEY_SECRET  = ...
//      HERE_TOKEN_ENDPOINT_URL = https://account.api.here.com/oauth2/token
//      HERE_CLIENT_ID          = ...
//      HERE_USER_ID            = ...
//      HERE_JS_API_KEY         = ...   (Maps JS SDK only — Hot Zones heatmap)
//
//  Info.plist (populated from xcconfig at build time via
//  `INFOPLIST_KEY_HERE*`):
//      HEREAccessKeyId, HEREAccessKeySecret, HERETokenEndpointURL,
//      HEREClientId, HEREUserId, HEREJSApiKey
//
//  Legacy: the previous HERE Platform apiKey was
//      // REDACTED — rotated 2026-04-22
//  and is now invalid at the HERE portal. Do not restore.
//
//  Powered by ESANG AI™.
//

import Foundation

enum HereMapsConfig {

    // MARK: - Info.plist keys

    /// OAuth1.0a consumer key id used to sign the `/oauth2/token` request.
    static let accessKeyIdPlistKey     = "HEREAccessKeyId"
    /// OAuth1.0a consumer secret — participates in the HMAC-SHA256 signing key.
    static let accessKeySecretPlistKey = "HEREAccessKeySecret"
    /// Full token endpoint URL, e.g. `https://account.api.here.com/oauth2/token`.
    static let tokenEndpointURLPlistKey = "HERETokenEndpointURL"
    /// Informational HERE client identifier (not used in signing).
    static let clientIdPlistKey        = "HEREClientId"
    /// Informational HERE user identifier (not used in signing).
    static let userIdPlistKey          = "HEREUserId"
    /// HERE Maps JS 3.1 apiKey — used ONLY by the Hot Zones heatmap
    /// WebView. The JS SDK does not accept OAuth Bearer tokens, so this
    /// is a separate, JS-scoped credential.
    static let jsApiKeyPlistKey        = "HEREJSApiKey"

    // MARK: - Base URLs

    /// Routing API v8  — truck-aware route computation.
    /// https://developer.here.com/documentation/routing-api/
    static let routingBaseURL = URL(string: "https://router.hereapi.com/v8/routes")!

    /// Matrix Routing API v8 — many-to-many cost matrix for dispatch.
    /// https://developer.here.com/documentation/matrix-routing-api/
    static let matrixBaseURL = URL(string: "https://matrix.router.hereapi.com/v8/matrix")!

    /// Geocoding & Search API v7 — forward geocoding (address → lat/lng).
    /// https://developer.here.com/documentation/geocoding-search-api/
    static let geocodeBaseURL = URL(string: "https://geocode.search.hereapi.com/v1/geocode")!

    /// Reverse geocoding — lat/lng → address.
    static let reverseGeocodeBaseURL = URL(string: "https://revgeocode.search.hereapi.com/v1/revgeocode")!

    /// Autosuggest — partial address lookups for pickers.
    static let autosuggestBaseURL = URL(string: "https://autosuggest.search.hereapi.com/v1/autosuggest")!

    /// Isoline Routing API v8 — drive-time polygons (geofence "within 30 min" etc).
    static let isolineBaseURL = URL(string: "https://isoline.router.hereapi.com/v8/isolines")!

    /// Traffic API v7 — incidents + flow overlays.
    static let trafficBaseURL = URL(string: "https://data.traffic.hereapi.com/v7")!

    /// Maps Tile API v3 (raster PNG). Authenticated via `Authorization: Bearer`
    /// on the request (not a query param) — see `HereTileOverlay.swift`.
    ///
    /// Example rendered:
    ///   https://maps.hereapi.com/v3/base/mc/12/1204/1540/512/png?style=explore.day&ppi=400
    static let tileBaseHost = "maps.hereapi.com"
    static let tileBasePath = "/v3/base/mc"

    // MARK: - Info.plist readers

    /// Reads a string from Info.plist, rejecting empty strings and
    /// unsubstituted `$(...)` placeholders (which indicate the xcconfig
    /// pipeline didn't run — typical for fresh SwiftPM test hosts).
    private static func plistString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty,
              !raw.hasPrefix("$(") else { return nil }
        return raw
    }

    static var accessKeyId: String?     { plistString(accessKeyIdPlistKey) }
    static var accessKeySecret: String? { plistString(accessKeySecretPlistKey) }
    static var clientId: String?        { plistString(clientIdPlistKey) }
    static var userId: String?          { plistString(userIdPlistKey) }

    /// Defaults to HERE's production token endpoint if the xcconfig was
    /// skipped — lets the app keep booting in dev without failing loudly.
    static var tokenEndpointURL: URL? {
        if let raw = plistString(tokenEndpointURLPlistKey),
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://account.api.here.com/oauth2/token")
    }

    /// Maps JS SDK apiKey (Hot Zones heatmap). Nil when the JS key
    /// hasn't been provisioned yet — callers should render the existing
    /// "no credentials" placeholder.
    static var jsApiKey: String? { plistString(jsApiKeyPlistKey) }

    // MARK: - Bearer token (REST APIs)

    /// Returns a valid HERE OAuth Bearer token, exchanging / refreshing
    /// as needed. Callers should pass the result into
    /// `Authorization: Bearer <token>` on every REST request.
    ///
    /// Throws `HereMapsError.missingAPIKey` if the xcconfig wasn't
    /// wired, or `HereMapsError.http` / `.providerError` on network
    /// failures against `/oauth2/token`.
    static func requireBearerToken() async throws -> String {
        try await HEREAuthService.shared.currentToken()
    }

    /// True iff the OAuth credentials needed to mint a Bearer token are
    /// present in Info.plist. Sync — safe to call from SwiftUI
    /// `updateUIView` before deciding whether to attach the HERE tile
    /// overlay.
    static var hasBearerCredentials: Bool {
        accessKeyId != nil && accessKeySecret != nil && tokenEndpointURL != nil
    }
}

// MARK: - Errors

enum HereMapsError: Error, LocalizedError {
    case missingAPIKey
    case badURL
    case http(Int, String)
    case decoding(String)
    case emptyResponse
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "HERE credentials are missing. Add HERE_ACCESS_KEY_ID / HERE_ACCESS_KEY_SECRET / HERE_TOKEN_ENDPOINT_URL to your xcconfig."
        case .badURL:                  return "Invalid HERE Maps URL."
        case .http(let c, let m):      return "HERE Maps HTTP \(c): \(m)"
        case .decoding(let m):         return "HERE decoding failed: \(m)"
        case .emptyResponse:           return "HERE returned an empty response."
        case .providerError(let m):    return "HERE provider error: \(m)"
        }
    }
}

// MARK: - Tile style

/// HERE map tile styles matching EusoTrip's dark / light registers.
///
/// `explore.night` is HERE's dark vector style — roads glow, ocean is near-black.
/// `explore.day`   is the light counterpart.
///
/// Both are "explore" family (general-purpose) — see HERE docs for the full list
/// (lite.day, lite.night, topo.day, logistics.day, satellite.day, etc.).
enum HereTileStyle: String {
    case dark = "explore.night"
    case light = "explore.day"

    /// Higher DPI for retina displays. HERE accepts 100 / 200 / 250 / 320 / 400 / 500 ppi.
    var ppi: Int { 400 }

    /// Tile edge size in points (256 is the OSM / MapKit default; 512 is retina-friendly).
    var sizePx: Int { 512 }
}
