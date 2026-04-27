# HERE — Current State Audit (EusoTrip iOS)

Repo root: `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/`
Audit date: 2026-04-22

## 1. Current authentication scheme

**Single scheme: HERE Platform `apikey=` query parameter.** No OAuth, no bearer tokens, no JWT. Every REST call tacks `apikey=<value>` onto the query string; the HERE Maps JS bundle in the Hot Zones WebView passes the same string into `new H.service.Platform({ apikey: ... })`.

The key is read from `Bundle.main.object(forInfoDictionaryKey: "HEREApiKey")`, which is populated at build time from an xcconfig variable:

- xcconfig secret (git-ignored): `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip.xcconfig` line 10
  ```
  HERE_API_KEY = mC47DqcAl4_fs-jXWedMuPVTw8EYDcAkAwe7NG5NpaQ
  ```
- Sample template: `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip.xcconfig.sample` line 11 (placeholder `REPLACE_WITH_HERE_PLATFORM_API_KEY`)
- Pipeline into Info.plist: `EusoTrip.xcodeproj/project.pbxproj` lines 1045 and 1079:
  ```
  INFOPLIST_KEY_HEREApiKey = "$(HERE_API_KEY)";
  ```
- Accessor: `EusoTrip/Services/HereMaps/HereMapsConfig.swift:69-87` (`HereMapsConfig.apiKey` / `requireAPIKey()`)

Nothing in the repo currently issues `POST https://account.api.here.com/oauth2/token` or computes an HMAC-SHA256 OAuth 1.0a signature. There is no `HEREAuthService.swift`, no Keychain storage of HERE credentials, and no access-key / client-id / user-id are referenced anywhere.

## 2. HERE API surfaces in use

All base URLs live in `EusoTrip/Services/HereMaps/HereMapsConfig.swift:33-62`:

| Surface | Base URL | Client |
|---|---|---|
| Routing v8 (truck) | `https://router.hereapi.com/v8/routes` | `HereRoutingClient.swift:91-142` |
| Matrix Routing v8 | `https://matrix.router.hereapi.com/v8/matrix` | `HereMatrixClient.swift:64-101` |
| Geocoding v7 (forward) | `https://geocode.search.hereapi.com/v1/geocode` | `HereGeocodingClient.swift:39-58` |
| Reverse geocoding v7 | `https://revgeocode.search.hereapi.com/v1/revgeocode` | `HereGeocodingClient.swift:65-81` |
| Autosuggest v1 | `https://autosuggest.search.hereapi.com/v1/autosuggest` | `HereGeocodingClient.swift:89-106` |
| Isoline Routing v8 | `https://isoline.router.hereapi.com/v8/isolines` | declared in `HereMapsConfig.swift:50`; no call site yet |
| Traffic v7 | `https://data.traffic.hereapi.com/v7` | declared in `HereMapsConfig.swift:53`; no call site yet |
| Maps Tile v3 (raster) | `https://maps.hereapi.com/v3/base/mc/{z}/{x}/{y}/{size}/png` | `HereTileOverlay.swift:44-59` |
| Maps JS 3.1 (heatmap) | `https://js.api.here.com/v3/3.1/mapsjs-*.js` | `HotZonesWidget.swift:839-842` |

Every request path appends `apikey=<HERE_API_KEY>`.

## 3. Rendering surfaces

1. **`HereMapView` (SwiftUI → `MKMapView` + `HereTileOverlay`)** — `EusoTrip/Views/Components/HereMapView.swift:38-478`. This is the canonical map surface (driver home, Eusoboards, load detail). HERE raster tiles are drawn via `MKTileOverlay` with `canReplaceMapContent = true`; Apple's basemap is suppressed. **Task #58's intent ("Replace MKMapView base with HERE Maps JS WebView") is NOT realised as a generic JS WebView — `HereMapView` is still `MKMapView` + HERE raster tiles.** Only the Hot Zones heatmap uses HERE Maps JS (see below).
2. **`HotZonesHeatmapWebView` (SwiftUI → `WKWebView` hosting HERE Maps JS v3.1)** — `EusoTrip/Views/Driver/HotZonesWidget.swift:660-930`. Loads `mapsjs-core.js`, `mapsjs-service.js`, `mapsjs-ui.js`, `mapsjs-data.js` from `https://js.api.here.com/v3/3.1/…`, creates `new H.service.Platform({ apikey: "<key>" })` (line 853), renders an `H.data.heatmap.Provider`. Vector style `normal.day` / `normal.night` (line 821).
3. **MKMapView `applyBrandBasemap`** — `HereMapView.swift:296-308`. `.mutedStandard` Apple basemap runs underneath as a fallback only when the HERE tile overlay is missing. No HERE credentials touched here.

## 4. HERE call sites (iOS app code)

| File:line | Call |
|---|---|
| `EusoTrip/Views/Driver/DriverTabPanes.swift:456` | `HereRoutingClient.shared.route(for: load)` (active-trip polyline) |
| `EusoTrip/Views/Driver/DriverTabPanes.swift:391, 399, 679` | `HereMapView(...)` / `HereMapView.Lane` / `HereMapView.LoadMarker` |
| `EusoTrip/Views/Components/HereMapView.swift:252-279` | Constructs + manages `HereTileOverlay` |
| `EusoTrip/Views/Driver/HotZonesWidget.swift:518, 545, 737` | `HereTileOverlay` references + `HereMapsConfig.apiKey` into HTML |
| `EusoTrip/ViewModels/DriverHomeViewModel.swift` | Consumes `HereRoutingClient` results (per file-list reference) |

No direct HERE REST calls exist outside `EusoTrip/Services/HereMaps/`.

## 5. Hot Zones data pipeline

**Server-side, not direct HERE.** The iOS widget calls `EusoTripAPI.shared.hotZones.getRateFeed(...)` (`EusoTrip/Services/EusoTripAPI.swift:1791-1805`) → tRPC `hotZones.getRateFeed` on the EusoTrip backend. The server returns `[HotZoneEntry]` with lat/lng + demand tier; the iOS side only uses HERE to *render* those points. No HERE credentials are needed to source the data.

Task #37 ("Fix Hot Zones decode + rebuild heatmap with HERE") and #51 ("Add USA basemap to Hot Zones heatmap") appear to have landed the WebView heatmap shown in `HotZonesWidget.swift:660-930`.

## 6. Leaked / placeholder / risky keys

- **`mC47DqcAl4_fs-jXWedMuPVTw8EYDcAkAwe7NG5NpaQ`** is the current live HERE Platform apiKey. It appears in:
  - `EusoTrip.xcconfig:10` (source of truth, but this file is supposed to be gitignored — verify `.gitignore` actually excludes it; if it was ever committed, the key is leaked and should be revoked at the HERE portal).
  - `EusoTrip/Services/HereMaps/HereMapsConfig.swift:10` (in a doc comment — a documentation leak; strip before any PR).
- The `.sample` file uses `REPLACE_WITH_HERE_PLATFORM_API_KEY` as placeholder; that is correct.
- No `YOUR_API_KEY`, `TODO HERE`, or `FIXME HERE` markers in active Swift sources.

## 7. Hardcoded coords / base URLs

- `HotZonesWidget.swift:669-671` hardcodes the CONUS-wide camera: `(39.8283, -98.5795)` at zoom 4. Safe (no auth dependency).
- All HERE base URLs are centralised in `HereMapsConfig.swift:33-62`. Migrating to OAuth does not require any URL change — the hosts (`router.hereapi.com`, `geocode.search.hereapi.com`, etc.) accept both apiKey and Bearer-token auth.

## 8. Summary

- **Auth scheme today: apiKey query parameter only.** Single key, single Info.plist entry, no refresh logic, no Keychain.
- **No existing OAuth, HMAC, token exchange, or refresh code to replace.** This is an additive migration.
- **7 Swift files touch HERE config/clients**, plus `HereMapView.swift` and `HotZonesWidget.swift` (2 call-site clusters), plus `EusoTripAPI.swift` (consumes server Hot Zones), and the build system (`EusoTrip.xcconfig`, `project.pbxproj`). Any OAuth migration centralises in `HereMapsConfig.swift` + new `HEREAuthService.swift`; the four client actors each need to switch from `apikey=` query param to `Authorization: Bearer …` header.
- **The HERE Maps JS bundle in the heatmap WebView currently uses `apikey`, not OAuth.** HERE's JS SDK does **not** accept Bearer tokens directly — `H.service.Platform` requires `{ apikey: ... }` or the (legacy) `app_id`/`app_code` pair. This is the single biggest scope risk (see risks.md §1).
