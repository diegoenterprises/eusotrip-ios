# HERE OAuth2 Migration — Risks & Blockers

Audit date: 2026-04-22

## 1. **[BLOCKER — UNVERIFIED]** HERE Maps JS bundle probably still needs an apiKey

The Hot Zones heatmap (`EusoTrip/Views/Driver/HotZonesWidget.swift:660-930`) embeds HERE Maps JS v3.1. At line 853 it calls:

```js
var platform = new H.service.Platform({ apikey: "<key>" });
```

`H.service.Platform` is documented to accept:
- `apikey: <string>` (Platform REST key) — current scheme.
- `app_id` + `app_code` — legacy freemium.
- In some versions, a `getRequestOptions()` or `useHTTPS`/`useCIT` flag.

**HERE's JS SDK v3.1 does NOT ship a first-class "Bearer token" constructor option.** You can sometimes set `H.service.Platform.prototype.config.token` manually after instantiation, but that is undocumented and has broken between minor releases. For production use, HERE recommends either (a) provisioning a **separate JS-specific apiKey** from the HERE portal, or (b) migrating the heatmap to a native renderer on iOS.

**Impact:** the five OAuth credentials we received cover all REST APIs (Routing, Matrix, Geocoding, Tile, Isoline, Traffic) but **likely do NOT cover the JS bundle**. We will need either:
- a **JS apiKey** issued from the HERE portal in addition to the OAuth client-credentials set, **or**
- a refactor to render the heatmap natively (`MKMapView` + custom tile overlay + precomputed density grid), eliminating the WebView entirely.

**Action before Commit 4 lands:** confirm with HERE developer support (or the project portal) whether the JS SDK can be initialized with a Bearer token. If not, request a JS apiKey.

## 2. **[HIGH]** Tile endpoint header injection

`HereTileOverlay.swift:44-59` today returns a URL with `apiKey=` in the query string — this is the only way to authenticate a tile fetch when you just return a URL. For OAuth you MUST override `loadTile(at:result:)` instead of `url(forTilePath:)` so you can attach the `Authorization: Bearer …` header to the request.

**Risk:** doing this naively bypasses `URLCache`. The proposed implementation in `here_integration_plan.md §4` uses `URLSession.shared.data(for:)` which DOES participate in the default cache. Verify this empirically: without it, every pan/zoom will re-exchange tokens and refetch tiles, wrecking data usage and map responsiveness.

## 3. **[HIGH]** Current apiKey may be leaked

The live HERE apiKey `mC47DqcAl4_fs-jXWedMuPVTw8EYDcAkAwe7NG5NpaQ` appears in:

- `EusoTrip.xcconfig:10` (should be gitignored — **verify**).
- `EusoTrip/Services/HereMaps/HereMapsConfig.swift:10` (documentation comment — committed to source control).

If either is in git history, the key is compromised. **Rotate the apiKey at the HERE portal** and strip the inline comment before the OAuth migration lands.

## 4. **[MEDIUM]** Quota tier & rate-limit differences between apiKey and OAuth

HERE's developer tiers (Freemium, Base, Pro) meter OAuth-token-backed requests the same way as apiKey requests — per plan per month. However, the token-exchange endpoint itself (`/oauth2/token`) is rate-limited to a small burst (HERE docs suggest 5–10 req/min). If a bug causes the app to exchange a fresh token on every REST call instead of reusing the cached one, the app will 429 quickly.

**Mitigation:** the `HEREAuthService` caching logic + in-flight coalescing in `here_auth_service.swift`. Add a debug log when a fresh exchange fires; in QA, confirm a 24 h session issues exactly one exchange.

## 5. **[MEDIUM]** HERE REST endpoint Bearer compatibility

The REST APIs listed in `HereMapsConfig.swift:33-62` all accept `Authorization: Bearer …`, confirmed by HERE docs for:
- Routing v8, Matrix v8, Geocoding v7, Autosuggest v1, Isoline v8, Traffic v7.
- Map Tile API v3.

However, the *exact* header name HERE expects has varied across minor updates. Before rolling out widely, add an integration test that hits `/v8/routes` with a Bearer token and asserts 200.

## 6. **[MEDIUM]** SDK version pinning

The heatmap WebView hardcodes `https://js.api.here.com/v3/3.1/mapsjs-*.js` (HotZonesWidget.swift:839-842). HERE occasionally ships breaking changes in 3.1.x patch releases. A bad tile-style change or API refactor would break the widget remotely. Consider: (a) pinning to a specific 3.1 patch build, or (b) bundling the JS locally. Out of scope for this OAuth migration but worth flagging.

## 7. **[LOW]** Clock skew

HERE's OAuth1.0a signature uses `oauth_timestamp = Unix seconds`. If the iPhone's clock is off by more than 5 minutes (rare but possible offline for long stretches), HERE will reject the signature. The service handles this by surfacing `HereMapsError.http(401, …)`; the user sees a retry loop.

**Mitigation:** consider a soft-fail path that asks the user to enable "Set Date & Time Automatically". Low priority.

## 8. **[LOW]** Keychain access during cold start

`HEREAuthService.loadFromKeychain()` uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. If the user cold-launches the app while the device is locked (e.g. via a complication tap), the Keychain read returns `errSecInteractionNotAllowed`. The service correctly falls through to a fresh exchange in that case, but first-launch UX on the Driver Home will pay a ~200 ms network hit. Acceptable.

## 9. **[LOW]** `user.id` and `client.id` unused

The provided credential set includes `here.user.id` and `here.client.id` but neither participates in the OAuth1.0a signature or the `/oauth2/token` request body. They are informational — useful for logging / support tickets, not for auth. We store them in Info.plist for completeness and to support future HERE features that may require them (e.g., attribution in analytics dashboards).

## 10. **[INFO]** Scope coverage summary

| Surface | New OAuth creds cover it? |
|---|---|
| Routing v8 (truck) | Yes |
| Matrix v8 | Yes |
| Geocoding / Reverse / Autosuggest | Yes |
| Maps Tile v3 raster (HereTileOverlay) | Yes (requires header injection — see §2) |
| Isoline v8 | Yes (not yet called) |
| Traffic v7 | Yes (not yet called) |
| **Maps JS 3.1 (Hot Zones heatmap WebView)** | **Probably no — see §1** |

## 11. **[INFO]** HERE portal audit

After the migration lands:
1. Revoke the old apiKey `mC47DqcAl4_fs-jXWedMuPVTw8EYDcAkAwe7NG5NpaQ` at the HERE portal.
2. Tag the new OAuth client `A8wYxsmwZBEqBIud1Jmc` with environment (prod / staging) and an owner contact.
3. Set per-API usage alerts (Routing and Tile are the biggest spenders in the current traffic profile).

---

**Biggest single blocker:** whether the OAuth credentials alone are sufficient for the HERE Maps JS bundle used in the Hot Zones heatmap (§1). If not, a separate JS apiKey must be obtained from the HERE portal before Commit 4 can land, or the heatmap must be refactored to a native renderer.
