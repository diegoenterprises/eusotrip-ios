# HERE OAuth2 Integration Plan — EusoTrip iOS

Targets: swap the existing `apikey=<key>` query-parameter scheme for HERE's
OAuth 2.0 client-credentials flow (OAuth1.0a-signed token exchange → 24 h Bearer).
Audit date: 2026-04-22. Awaiting green-light before any code lands.

## 0. Credential set (new)

| Field | Value |
|---|---|
| `here.user.id` | `HERE-7239406a-1b48-45b5-9964-fb81d7a73a7a` |
| `here.client.id` | `A8wYxsmwZBEqBIud1Jmc` |
| `here.access.key.id` | `aFi-kDtCV1dbeQjNR0SKWw` |
| `here.access.key.secret` | `tu2LygcYLwnqBsPV0sgZ_PfFbZBquNoBrcwcKbaxJuGZIK48APnmLycnYKULfdLVcvBvz9tOpAbWoqIWcxtlNA` |
| `here.token.endpoint.url` | `https://account.api.here.com/oauth2/token` |

Only `access.key.id` and `access.key.secret` actually participate in the signature. `user.id` and `client.id` are informational.

## 1. Token-exchange mechanics (what `HEREAuthService` must do)

HERE's "app credentials" flow is OAuth1.0a-HMAC-SHA256 → OAuth2 token exchange. Each call to `POST https://account.api.here.com/oauth2/token`:

1. Build the **OAuth1.0a base string**:
   - HTTP method uppercase: `POST`
   - Percent-encoded endpoint URL (no query): `https%3A%2F%2Faccount.api.here.com%2Foauth2%2Ftoken`
   - Percent-encoded, alpha-sorted params (merged from body and OAuth header):
     - Body: `grant_type=client_credentials`
     - OAuth header: `oauth_consumer_key=<access.key.id>`, `oauth_nonce=<16-byte random>`, `oauth_signature_method=HMAC-SHA256`, `oauth_timestamp=<unix-seconds>`, `oauth_version=1.0`
   - Join `METHOD&URL&PARAMS` each percent-encoded once more.
2. **Signing key** = `percentEncode(access.key.secret) + "&"` (no token secret; trailing `&` is mandatory).
3. `HMAC-SHA256(signingKey, baseString)` → base64 → percent-encode → `oauth_signature`.
4. Send:
   ```
   POST /oauth2/token HTTP/1.1
   Host: account.api.here.com
   Authorization: OAuth oauth_consumer_key="…",oauth_signature_method="HMAC-SHA256",
                       oauth_timestamp="…",oauth_nonce="…",oauth_version="1.0",
                       oauth_signature="…"
   Content-Type: application/x-www-form-urlencoded

   grant_type=client_credentials
   ```
5. Response: `{ "access_token": "eyJhbGciOi…", "token_type": "bearer", "expires_in": 86399 }`.
6. Cache `access_token` until `issuedAt + expires_in − 30 min`; refresh proactively before that.

The proposed Swift implementation in `here_auth_service.swift` handles all of this. See §3 for wiring.

## 2. Files and ordering

The migration lands in three commits (each compiles independently). Any deeper cut should be blocked by the OAuth bundle-key question (risks.md §1).

### Commit 1 — Secret scaffolding (no behaviour change)

| # | File | Change |
|---|---|---|
| 1 | `EusoTrip.xcconfig` | Add `HERE_ACCESS_KEY_ID`, `HERE_ACCESS_KEY_SECRET`, `HERE_TOKEN_URL`, `HERE_CLIENT_ID`, `HERE_USER_ID`. Keep existing `HERE_API_KEY` until §3 lands. |
| 2 | `EusoTrip.xcconfig.sample` | Mirror new keys with `REPLACE_*` placeholders; delete the inline comment that leaks a key path. |
| 3 | `EusoTrip.xcodeproj/project.pbxproj` | Add `INFOPLIST_KEY_HEREAccessKeyId`, `INFOPLIST_KEY_HEREAccessKeySecret`, `INFOPLIST_KEY_HERETokenURL`, `INFOPLIST_KEY_HEREClientId`, `INFOPLIST_KEY_HEREUserId` on both Debug and Release configurations (companion to existing `INFOPLIST_KEY_HEREApiKey` at pbxproj lines 1045 + 1079). |
| 4 | `EusoTrip/Services/HereMaps/HereMapsConfig.swift` | Add `accessKeyId`, `accessKeySecret`, `tokenEndpointURL`, `clientId`, `userId` Info.plist readers next to existing `apiKey`. Strip the leaked key from the top-of-file comment. Keep `apiKey` for now (heatmap WebView depends on it). |
| 5 | `EusoTrip/Services/HereMaps/HERE.plist` *(new, optional)* | If stakeholders prefer a separate plist over xcconfig injection, ship one — still gitignored. Default plan stays on xcconfig so CI/TestFlight keeps working. |

### Commit 2 — Auth service + token caching

| # | File | Change |
|---|---|---|
| 6 | `EusoTrip/Services/HereMaps/HEREAuthService.swift` *(new)* | Actor implementing OAuth1.0a-signed token exchange + in-memory & Keychain cache + background refresh. Full proposed source in `here_auth_service.swift`. |
| 7 | `EusoTrip/Services/HereMaps/HereMapsConfig.swift` | Add `static func requireBearerToken() async throws -> String` that proxies to `HEREAuthService.shared.currentToken()`. Keep `requireAPIKey()` alive during migration. |
| 8 | Unit test (optional) | `EusoTripTests/HereMaps/HEREAuthServiceTests.swift` — feed a fixed nonce + timestamp + known-good HERE test vector and assert the computed signature matches the reference string. |

### Commit 3 — Switch REST clients to Bearer auth

| # | File | Change |
|---|---|---|
| 9 | `HereRoutingClient.swift:91-127` | Remove `URLQueryItem(name: "apikey", …)` (line 95). Build `URLRequest`; set `req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")` where `token = try await HereMapsConfig.requireBearerToken()`. `session.data(for: req)` instead of `session.data(from: url)`. Keep a single retry: on HTTP 401, call `HEREAuthService.shared.invalidate()` then retry once. |
| 10 | `HereGeocodingClient.swift:39-106` | Same treatment for `geocode`, `reverseGeocode`, `autosuggest` (3 call sites). |
| 11 | `HereMatrixClient.swift:64-101` | Drop `apikey` query item (line 67); add Bearer header on the existing `URLRequest`. |
| 12 | `HereTileOverlay.swift:44-59` | **Decision needed.** Map Tile API v3 accepts OAuth Bearer on the `Authorization` header, but `MKTileOverlay.url(forTilePath:)` returns a URL only — there is no hook to set request headers. Two options: (a) subclass `MKTileOverlay` and override `loadTile(at:result:)` to make the request manually with a Bearer header; (b) keep the tile endpoint on apiKey and issue an explicit "tile apikey" from the HERE portal. Recommend (a) — same OAuth credentials, no second secret. Full implementation sketch in §4. |

### Commit 4 — Heatmap WebView (conditional)

| # | File | Change |
|---|---|---|
| 13 | `HotZonesWidget.swift:660-930` | **If HERE confirms the JS SDK can consume an OAuth Bearer** (we have not verified this — see risks.md §1), swap `new H.service.Platform({ apikey: apiKey })` on line 853 for `{ token: bearer }` or equivalent. **If not**, keep an apiKey-flavoured credential for this one surface and document that the OAuth creds alone do NOT cover the HERE Maps JS bundle. |

## 3. How call sites change (shape, not bytes)

Every REST client today looks like:

```swift
let key = try HereMapsConfig.requireAPIKey()
comps.queryItems = [URLQueryItem(name: "apikey", value: key), …]
let (data, resp) = try await session.data(from: url)
```

After migration:

```swift
let token = try await HereMapsConfig.requireBearerToken()
comps.queryItems = [ … ]                       // no apikey entry
var req = URLRequest(url: comps.url!)
req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
let (data, resp) = try await session.data(for: req)
if (resp as? HTTPURLResponse)?.statusCode == 401 {
    await HEREAuthService.shared.invalidate()
    let retryToken = try await HereMapsConfig.requireBearerToken()
    req.setValue("Bearer \(retryToken)", forHTTPHeaderField: "Authorization")
    // one more attempt
}
```

## 4. `HereTileOverlay` specifics

Current implementation (`HereTileOverlay.swift:44-59`) builds a URL with `apiKey` and `style` in the query string. To move to Bearer:

```swift
override func loadTile(at path: MKTileOverlayPath,
                      result: @escaping (Data?, Error?) -> Void) {
    Task {
        do {
            let token = try await HereMapsConfig.requireBearerToken()
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host   = HereMapsConfig.tileBaseHost
            comps.path   = "\(HereMapsConfig.tileBasePath)/\(path.z)/\(path.x)/\(path.y)/\(style.sizePx)/png"
            comps.queryItems = [
                URLQueryItem(name: "style", value: style.rawValue),
                URLQueryItem(name: "ppi",   value: String(style.ppi))
            ]
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
            result(data, nil)
        } catch {
            result(nil, error)
        }
    }
}
```

Note: `URLSession` caching still works because Foundation keys the cache on URL, not headers — tiles with identical `{z}/{x}/{y}` will cache-hit across token refreshes.

## 5. Token caching

**In-memory** (primary): an actor-isolated `struct CachedToken { token: String; expiresAt: Date }` in `HEREAuthService`. Re-entrant callers await the same `Task` during a refresh to avoid thundering-herd.

**Keychain** (secondary, for cold start): store `token` + `expiresAt` under service `"com.eusorone.eusotrip.hereoauth"` account `"bearer"` using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Survives app relaunch but not device transfer. A valid cached token avoids the first network round-trip on cold launch, so the first tile request doesn't block on token exchange.

**Background refresh**: 30 min before expiry, `HEREAuthService` schedules a `Task.detached` to exchange a fresh token. If refresh fails, the stale-but-still-valid token stays in cache — next REST call will retry.

## 6. Fallback behaviour

1. **Airplane mode / no network on first launch.** `requireBearerToken()` throws; REST clients surface `HereMapsError.providerError`. UI already degrades gracefully: `HereMapView.updateUIView` (line 271) already handles the "no api key" branch by removing the tile overlay and letting the muted Apple basemap show through. We extend the same path to include "no token available".
2. **HERE outage / 5xx from `/oauth2/token`.** `HEREAuthService` exponentially backs off (1 s, 2 s, 4 s, max 3 retries) then surfaces the error. Cached token stays in use until its real expiry.
3. **Token revoked mid-session (401 on a REST call).** Client invalidates cache once, re-exchanges, retries the original request exactly once. On second 401 → surface error.
4. **WebView heatmap with bad credentials.** Existing "HERE API key not configured" placeholder (`HotZonesWidget.swift:807-818`) already renders. Extend message text to mention OAuth when the migration lands.

## 7. Secure storage decision

- Ship credentials via xcconfig → Info.plist (existing pattern). `EusoTrip.xcconfig` is gitignored (verify before commit).
- Reading happens in `HereMapsConfig.swift`.
- Bearer token ends up in **Keychain only** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Never written to UserDefaults or disk plists.
- `here.access.key.secret` stays in Info.plist, **never** copied to Keychain, and **never** sent to the EusoTrip backend.

## 8. Dependency ordering

```
Commit 1 (secret scaffolding)
    │
    └─▶ Commit 2 (HEREAuthService)
            │
            └─▶ Commit 3 (REST clients switch)
                    │
                    └─▶ Commit 4 (heatmap WebView — conditional on HERE docs verification)
```

Each commit builds green; the app keeps using apiKey at each step until Commit 3 lands. Rollback at any step is a revert of that commit with no data migration.

## 9. Out of scope (flag for later)

- Isoline + Traffic + Discover API adoption (URLs declared in `HereMapsConfig.swift:50, 53` but no call sites yet).
- Server-side HERE calls (none today — Hot Zones data comes from EusoTrip's own tRPC).
- Watch app: has no HERE usage; no change needed.
- Certificate pinning for HERE hosts: not currently implemented; consider separately.
