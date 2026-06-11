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
//  ─────────────────────────────────────────────────────────────────────
//  ENTERPRISE SEAM (HERE basic → enterprise migration)
//
//  HERE is moving this account from the basic/public tier to a dedicated
//  enterprise tier. When their team hands over the enterprise endpoints +
//  keys, the swap is a SINGLE, OBVIOUS change — see `HereTier` and the
//  `ENTERPRISE SWAP` blocks below:
//    1. Flip `activeTier` from `.basic` to `.enterprise`.
//    2. Fill `enterpriseHosts` with the per-service enterprise hosts HERE
//       provides (routing / matrix / geocoding / tiles / isoline / traffic).
//    3. Drop the enterprise credentials into the SAME xcconfig keys below —
//       no new symbols, no code change. (If enterprise mints tokens from a
//       different `/oauth2/token` host, that already flows through the
//       existing `HERE_TOKEN_ENDPOINT_URL` xcconfig value.)
//  Until all three are done, leave `activeTier = .basic`: every accessor
//  resolves to today's public hosts, so behavior is unchanged. NO fake or
//  placeholder enterprise credentials are staged — the enterprise host map
//  ships empty and falls back to the basic hosts.
//  ─────────────────────────────────────────────────────────────────────
//
//  Powered by ESANG AI™.
//

import Foundation

/// HERE Platform service tier. The account is migrating basic → enterprise;
/// this is the single switch that selects which set of host endpoints the
/// REST clients hit. Credentials are read from the SAME xcconfig/Info.plist
/// keys regardless of tier (see `HereMapsConfig`'s readers) — only the host
/// endpoints differ, so swapping tiers never touches the OAuth flow.
enum HereTier {
    /// Public `*.hereapi.com` hosts on the basic plan. Current production.
    case basic
    /// Dedicated enterprise hosts handed over by the HERE team. Endpoints
    /// live in `HereMapsConfig.enterpriseHosts`; not active until that map
    /// is populated and `activeTier` is flipped to `.enterprise`.
    case enterprise
}

enum HereMapsConfig {

    // MARK: - Tier selection (ENTERPRISE SWAP point #1)

    /// The HERE service tier all REST clients route through.
    ///
    /// 2026-06-09 ENTERPRISE SWAP EXECUTED: HERE handed over the enterprise
    /// apiKey (now in `HERE_JS_API_KEY` xcconfig) and upgraded the account
    /// in place — live-probed same day: `explore.night` / `logistics.night`
    /// raster tiles now return 200 over Bearer (403'd on basic), and the
    /// existing OAuth client-credentials still mint (HTTP 200, 24 h expiry).
    /// HERE did NOT issue dedicated per-service hosts — the public
    /// `*.hereapi.com` hosts carry the enterprise entitlements — so
    /// `enterpriseHosts` stays empty and resolves to the public hosts.
    static let activeTier: HereTier = .enterprise

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

    /// Origin presented as the WKWebView document `baseURL` when hosting
    /// the HERE Maps JS SDK. This becomes the HTTP `Referer` on every
    /// OMV tile / style request, which HERE validates against the apiKey's
    /// TRUSTED-DOMAINS list (developer.here.com/tutorials/how-to-secure-
    /// your-here-apikey). It MUST be a domain whitelisted in the HERE
    /// portal for `HEREJSApiKey`.
    ///
    /// 2026-05-21: was implicitly `https://js.api.here.com` (HERE's own
    /// CDN, NOT whitelisted) → every tile 403'd → blank map on every iOS
    /// surface. Set to the production web origin, which is already
    /// whitelisted (the web platform renders fine from it). If the web
    /// app is served from a different host (e.g. app.eusotrip.com),
    /// change this ONE constant to match the portal trusted-domains list.
    static let jsTrustedReferrerOrigin = "https://eusotrip.com"

    // MARK: - Per-service host map (ENTERPRISE SWAP point #2)

    /// One HERE REST service. Each case owns a basic (public) host and an
    /// enterprise host slot; `host` returns the right one for `activeTier`.
    /// The PATHs (v8/routes, v1/geocode, …) are stable across tiers and live
    /// with the base-URL accessors below — only the HOST changes per tier.
    enum Service {
        case routing, matrix, geocode, reverseGeocode, autosuggest, isoline, traffic, tile

        /// Public `*.hereapi.com` host on the basic plan. Current production.
        var basicHost: String {
            switch self {
            case .routing:        return "router.hereapi.com"
            case .matrix:         return "matrix.router.hereapi.com"
            case .geocode:        return "geocode.search.hereapi.com"
            case .reverseGeocode: return "revgeocode.search.hereapi.com"
            case .autosuggest:    return "autosuggest.search.hereapi.com"
            case .isoline:        return "isoline.router.hereapi.com"
            case .traffic:        return "data.traffic.hereapi.com"
            case .tile:           return "maps.hereapi.com"
            }
        }
    }

    /// Enterprise host overrides, keyed by `Service`.
    ///
    /// ENTERPRISE SWAP: when HERE hands over the enterprise endpoints, drop
    /// each enterprise host here, e.g.
    ///     [.routing: "routing.enterprise.<tenant>.here.com",
    ///      .tile:    "tiles.enterprise.<tenant>.here.com", …]
    /// A `Service` missing from this map falls back to its `basicHost`, so a
    /// partial enterprise rollout is safe. Ships EMPTY today — no fake hosts
    /// staged — so `.enterprise` would currently resolve to the basic hosts.
    static let enterpriseHosts: [Service: String] = [:]

    /// Resolves the live host for `service` under the active tier: the
    /// enterprise override when on `.enterprise` and one is provided,
    /// otherwise the basic public host.
    static func host(for service: Service) -> String {
        switch activeTier {
        case .basic:
            return service.basicHost
        case .enterprise:
            return enterpriseHosts[service] ?? service.basicHost
        }
    }

    // MARK: - Base URLs (host = tier-resolved, path = tier-stable)

    /// Routing API v8  — truck-aware route computation.
    /// https://developer.here.com/documentation/routing-api/
    static var routingBaseURL: URL { URL(string: "https://\(host(for: .routing))/v8/routes")! }

    /// Matrix Routing API v8 — many-to-many cost matrix for dispatch.
    /// https://developer.here.com/documentation/matrix-routing-api/
    static var matrixBaseURL: URL { URL(string: "https://\(host(for: .matrix))/v8/matrix")! }

    /// Geocoding & Search API v7 — forward geocoding (address → lat/lng).
    /// https://developer.here.com/documentation/geocoding-search-api/
    static var geocodeBaseURL: URL { URL(string: "https://\(host(for: .geocode))/v1/geocode")! }

    /// Reverse geocoding — lat/lng → address.
    static var reverseGeocodeBaseURL: URL { URL(string: "https://\(host(for: .reverseGeocode))/v1/revgeocode")! }

    /// Autosuggest — partial address lookups for pickers.
    static var autosuggestBaseURL: URL { URL(string: "https://\(host(for: .autosuggest))/v1/autosuggest")! }

    /// Isoline Routing API v8 — drive-time polygons (geofence "within 30 min" etc).
    static var isolineBaseURL: URL { URL(string: "https://\(host(for: .isoline))/v8/isolines")! }

    /// Traffic API v7 — incidents + flow overlays.
    static var trafficBaseURL: URL { URL(string: "https://\(host(for: .traffic))/v7")! }

    /// Maps Tile API v3 (raster PNG). Authenticated via `Authorization: Bearer`
    /// on the request (not a query param) — see `HereTileOverlay.swift`.
    ///
    /// Example rendered:
    ///   https://maps.hereapi.com/v3/base/mc/12/1204/1540/512/png?style=explore.day&ppi=400
    static var tileBaseHost: String { host(for: .tile) }
    static let tileBasePath = "/v3/base/mc"

    // MARK: - Info.plist readers (ENTERPRISE SWAP point #3 — credentials)

    /// All HERE credentials are read from Info.plist (populated from the
    /// git-ignored xcconfig at build time), regardless of tier.
    ///
    /// ENTERPRISE SWAP: when HERE issues the enterprise OAuth credentials,
    /// replace the values of the SAME xcconfig keys — no symbols change here:
    ///   HERE_ACCESS_KEY_ID      → `accessKeyIdPlistKey`     (HEREAccessKeyId)
    ///   HERE_ACCESS_KEY_SECRET  → `accessKeySecretPlistKey` (HEREAccessKeySecret)
    ///   HERE_TOKEN_ENDPOINT_URL → `tokenEndpointURLPlistKey` (only if the
    ///                             enterprise token host differs from
    ///                             account.api.here.com/oauth2/token)
    ///   HERE_JS_API_KEY         → `jsApiKeyPlistKey` (Maps JS SDK / Hot Zones)
    /// No enterprise credential values are committed — the xcconfig is the
    /// single source of truth and stays git-ignored (honest vendor seam).

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
            // HERE Routing v8 also returns `detail` and a per-param
            // `parameter` field on 400-class rejections — those name
            // the EXACT param that failed parsing, which is the only
            // piece useful for debugging. Surface them all.
            let title     = (dict["title"]     as? String) ?? ""
            let cause     = (dict["cause"]     as? String) ?? ""
            let action    = (dict["action"]    as? String) ?? ""
            let detail    = (dict["detail"]    as? String) ?? ""
            let parameter = (dict["parameter"] as? String) ?? ""
            var parts = [title, cause, action, detail].filter { !$0.isEmpty }
            if !parameter.isEmpty {
                parts.append("param=\(parameter)")
            }
            if !parts.isEmpty {
                return parts.joined(separator: " · ")
            }
        }
        // Status-coded fallbacks for the common cases users hit.
        // When the body isn't recognizable JSON, append the first 200
        // chars of the raw body so we can diagnose unexpected error
        // shapes without re-instrumenting and re-shipping.
        let trimmedBody = body
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .prefix(200)
        let bodyTail = trimmedBody.isEmpty ? "" : " · raw: \(trimmedBody)"
        switch code {
        case 400: return "HTTP 400 — bad request\(bodyTail)"
        case 401: return "Routing auth expired — pull to refresh."
        case 403: return "Routing forbidden for this lane (plan tier or region restriction)."
        case 404: return "Lane not found in routing graph."
        case 429: return "Too many routing requests right now — try again in a moment."
        case 500...599: return "Routing service is having issues — try again."
        default:        return "Routing failed (status \(code))\(bodyTail)"
        }
    }
}

// MARK: - Tile style

/// HERE map tile styles matching EusoTrip's dark / light registers.
///
/// RETIRED FROM UI 2026-05-29 — `BespokeMapCanvas` is the shipping iOS
/// renderer and is the Eusorone basemap by construction. This raster
/// machinery is retained for the true-street fallback tier only.
///
/// REACTIVATION CONTRACT (_EUSORONE_BASEMAP_SPEC_2026-06-10 §3): the
/// raster path may ONLY return to the UI wearing the
/// `EusoroneTileRemapper` pipeline — fetched PNGs pass through a
/// per-register Core Image color-cube LUT (palette → Eusorone Day
/// `#E8EEF5` slate / Eusorone Night `#0B1120`) at LOAD time before they
/// reach MapKit. The pre-2026-06-10 note here praising `explore.day`'s
/// stock look ("mirror Apple Maps Standard") is SUPERSEDED by that
/// spec: stock HERE cartography — yellow motorways, cream land, green
/// parks, white label halos, cased roads — is rejected on every
/// surface, every register.
///
/// Under the contract BOTH registers remap from the single
/// `explore.day` upstream (never fetch `explore.night` — HERE's night
/// palette is HERE's, not ours; one upstream also halves URLCache and
/// rate-limiter pressure). The `nightStyleAvailable` 403-fallback
/// machinery below becomes dead at reactivation and is removed with it
/// (§3.2). Enterprise raster verified 200 over Bearer on 2026-06-09.
enum HereTileStyle {
    case dark
    case light

    /// HERE `style=` query param — the raw UPSTREAM stream, not a look
    /// we ever ship: at reactivation the fetched tile is palette-
    /// remapped by `EusoroneTileRemapper` before display (§3.2). Per
    /// the contract both registers will source `explore.day`; the
    /// `.dark → explore.night` branch survives only until the remapper
    /// lands, after which it and `nightStyleAvailable` are deleted.
    var rawValue: String {
        switch self {
        case .light: return "explore.day"
        case .dark:
            return HereTileStyle.nightStyleAvailable
                ? "explore.night"
                : "explore.day"
        }
    }

    /// Whether this style is currently rendering with HERE's real
    /// night raster (`explore.night`) or the day fallback. The former
    /// reader (`TintingTileOverlayRenderer`) was deleted in `8f710a3`;
    /// no live call sites remain. Kept only so the rollback path
    /// compiles — dies with `nightStyleAvailable` at reactivation,
    /// when night comes from the LUT remap instead of a HERE style.
    var isRenderingNightRaster: Bool {
        self == .dark && HereTileStyle.nightStyleAvailable
    }

    /// Process-wide flag flipped by `HereTileOverlay` the first time
    /// HERE returns 403 on an `explore.night` tile — once the tier
    /// rejects night once, every subsequent dark tile uses `.day`
    /// instead. Stays true (night-available) until that 403 is
    /// observed. DEAD at reactivation (§3.2): with both registers
    /// remapping from `explore.day` there is no night fetch to 403.
    nonisolated(unsafe) static var nightStyleAvailable: Bool = true

    /// HERE Raster Tile v3 now accepts ONLY 100 / 200 / 400 — the older
    /// 72/250/320/500 levels were dropped from the OpenAPI schema and
    /// return HTTP 400 `E622002` ("parameter does not match schema").
    /// That rejection hit EVERY tile request while this was 250, which
    /// is why no basemap rendered anywhere (verified live 2026-06-09:
    /// ppi=250 → 400, ppi=200 → 200 image/png). 200 keeps labels at the
    /// same readable ~14–16 pt physical size the 250 setting targeted —
    /// 400 re-creates the oversized-label problem, 100 is too small.
    var ppi: Int { 200 }

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
