//
//  HereMapsConfig.swift
//  EusoTrip — Central config for HERE Maps Platform integration
//
//  REST APIs (Routing, Matrix, Geocoding, Traffic, Weather, Parking, EV)
//  are accessed through authenticated EusoTrip backend procedures. HERE
//  OAuth credentials never enter the iOS bundle.
//
//  Xcconfig (e.g. `EusoTrip.xcconfig`, git-ignored):
//      HERE_JS_API_KEY         = ...   (Maps JS SDK basemap only)
//
//  Info.plist (populated from xcconfig at build time via
//  `INFOPLIST_KEY_HERE*`):
//      HEREJSApiKey
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
/// backend HERE clients hit. The iOS target uses this only to tune its local
/// request pacing and JS basemap presentation.
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

    /// HERE Maps JS 3.2 apiKey used by the shared labeled basemap renderer.
    /// This key must be restricted to the trusted referrer below.
    static let jsApiKeyPlistKey        = "HEREJSApiKey"
    static let customStylesEnabledPlistKey = "HERECustomMapStylesEnabled"

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

    /// Maps Tile API v3 host retained for diagnostics. Production iOS basemaps
    /// render through HERE Maps JS with the referrer-restricted JS key.
    ///
    /// Exact diagnostic shape (the dimensions are query parameters, not path
    /// segments):
    ///   https://maps.hereapi.com/v3/base/mc/12/1204/1540/png?style=explore.day&size=512&ppi=200&lang=en
    static var tileBaseHost: String { host(for: .tile) }
    static let tileBasePath = "/v3/base/mc"

    // MARK: - Info.plist reader (Maps JS key only)

    /// Reads a string from Info.plist, rejecting empty strings and
    /// unsubstituted `$(...)` placeholders (which indicate the xcconfig
    /// pipeline didn't run — typical for fresh SwiftPM test hosts).
    private static func plistString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty,
              !raw.hasPrefix("$(") else { return nil }
        return raw
    }

    /// Maps JS SDK apiKey for every native map surface. Nil when the key has
    /// not been provisioned; callers render the generic unavailable state.
    static var jsApiKey: String? { plistString(jsApiKeyPlistKey) }

    /// Release flag for the 18 mode/family/theme Style Editor archives.
    /// Disabled builds use the matching HERE family/theme openly; custom load
    /// failure is still shown as degraded. Enable only after archive, runtime,
    /// visual, and contrast gates.
    static var customMapStylesEnabled: Bool {
        if let value = Bundle.main.object(
            forInfoDictionaryKey: customStylesEnabledPlistKey
        ) as? Bool {
            return value
        }
        guard let raw = plistString(customStylesEnabledPlistKey)?.lowercased() else {
            return false
        }
        return ["1", "true", "yes"].contains(raw)
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
/// 2026-06-09 — ENTERPRISE: `explore.night` and `logistics.night`
/// verified 200 over Bearer on the upgraded account (the basic-tier
/// 403s are history). The shared Maps JS renderer consumes this compact
/// style type when legacy `HereMapView` call sites provide an override.
///
/// Dark-register feel comes from a SwiftUI tint overlay on the
/// MKMapView host (see `HereMapView.applyDarkOverlay(...)`) —
/// matches the web platform's brand-tint CSS overlay strategy.
///
/// "explore" family is general-purpose — HERE also offers
/// lite.day, topo.day, logistics.day, satellite.day, etc.
///
enum HereTileStyle {
    case dark
    case light

    /// HERE `style=` query param. Light → `explore.day` (cream roads,
    /// blue water, green parks — the look we want to mirror Apple
    /// Maps Standard from the founder's reference screenshot). Dark →
    /// `explore.night` for the dark register.
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
    /// night raster (`explore.night`) or the day-with-tint fallback.
    /// `TintingTileOverlayRenderer` reads this to decide whether to
    /// paint the dark slate-blue overlay (only needed when the day
    /// raster is being repurposed for night).
    var isRenderingNightRaster: Bool {
        self == .dark && HereTileStyle.nightStyleAvailable
    }

    /// Retained for compatibility with legacy style callers. The Maps JS
    /// renderer handles provider errors without exposing REST credentials.
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
