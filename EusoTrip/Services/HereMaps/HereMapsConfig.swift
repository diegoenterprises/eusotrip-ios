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
            // Internal — never user-facing; founder branding doctrine
            // strips 'HERE' from visible copy but the diagnostic
            // string stays explicit so dev can fix the xcconfig.
            return "Routing credentials missing — check xcconfig."
        case .badURL:                  return "Invalid routing URL."
        case .http(let c, let m):
            // HERE returns a JSON body on 4xx like
            //   {"title":"Malformed request","status":400,"cause":"...","action":"..."}
            // Default error path was concatenating the whole body
            // verbatim into the UI ('title malfor...'). Parse out
            // just the title / cause and surface a clean string.
            return Self.humanReadable(http: c, rawBody: m)
        case .decoding:                return "Couldn't read routing response — try again."
        case .emptyResponse:           return "Routing returned no result."
        case .providerError(let m):    return m
        }
    }

    /// Parse HERE's JSON error body and return a clean human string.
    /// Falls back to a status-coded fallback if the body isn't JSON.
    private static func humanReadable(http code: Int, rawBody body: String) -> String {
        if let data = body.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Prefer cause + action when present; fall back to title.
            let title  = (dict["title"]  as? String) ?? ""
            let cause  = (dict["cause"]  as? String) ?? ""
            let action = (dict["action"] as? String) ?? ""
            let parts = [title, cause, action].filter { !$0.isEmpty }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
        }
        // Status-coded fallbacks for the common cases users hit.
        switch code {
        case 400: return "Couldn't resolve that lane — try refining the addresses."
        case 401: return "Routing auth expired — pull to refresh."
        case 403: return "Routing forbidden for this lane (plan tier or region restriction)."
        case 404: return "Lane not found in routing graph."
        case 429: return "Too many routing requests right now — try again in a moment."
        case 500...599: return "Routing service is having issues — try again."
        default:        return "Routing failed (status \(code))."
        }
    }
}

// MARK: - Tile style

/// HERE map tile styles matching EusoTrip's dark / light registers.
///
/// IMPORTANT — both registers use `explore.day` because every
/// `*.night` YAML returns HTTP 403 on our HERE plan tier
/// (verified against `api.here.com` 2026-04-29 — see web commit
/// `3fc9d77e` for the full probe table). When the HERE plan
/// upgrades to a night-licensed tier, swap `dark.rawValue` back
/// to `explore.night`.
///
/// Dark-register feel comes from a SwiftUI tint overlay on the
/// MKMapView host (see `HereMapView.applyDarkOverlay(...)`) —
/// matches the web platform's brand-tint CSS overlay strategy.
///
/// "explore" family is general-purpose — HERE also offers
/// lite.day, topo.day, logistics.day, satellite.day, etc.
enum HereTileStyle {
    case dark
    case light

    /// HERE `style=` query param. Both cases resolve to `explore.day`
    /// per the 2026-04-29 fix; swap `dark` back to `"explore.night"`
    /// when the HERE plan upgrades to a night-licensed tier.
    var rawValue: String { "explore.day" }

    /// HERE accepts 72 / 100 / 200 / 250 / 320 / 400 / 500. We pair
    /// `ppi=250` with `size=512` so labels render at a normal-map size
    /// on iPhone retina (~14–16 pt physical) instead of the oversized
    /// 30–50 pt blocks you got with `ppi=400` (those were sized for a
    /// hypothetical 400-PPI desktop display, not iOS retina).
    var ppi: Int { 250 }

    /// HERE PNG dimension in PIXELS. We request 512 px so the asset is
    /// 2× the on-screen point-size MKTileOverlay paints (256 pt). That
    /// gives retina-friendly downsampling on iPhone 2x and 3x devices.
    var sizePx: Int { 512 }

    /// IETF BCP-47 language tag passed to HERE so labels stay in
    /// English worldwide. Without this the `explore.day` style falls
    /// back to local-language labels when you pan to Europe / Asia /
    /// LatAm — Cyrillic over Russia, Cyrillic+Latin over Bulgaria,
    /// Greek over Greece, Arabic over the Maghreb, etc. Forcing `en`
    /// matches the web platform's HERE basemap, which is also locked
    /// to English.
    var labelLanguage: String { "en" }
}
