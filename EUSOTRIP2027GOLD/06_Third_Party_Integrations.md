# 06 · Third-Party Integrations

**What this covers.** Every integration that crosses the EusoTrip process boundary — HERE Maps (OAuth1.0a + JS apiKey), Stripe (PaymentIntent, Connect, Adaptive Fee landmine), Plaid (planned), Apple frameworks (Sign in with Apple, Apple Pay, MapKit, CoreLocation, CoreMotion, HealthKit, App Intents, WeatherKit), ELD providers (Samsara primary + 10 more), FMCSA QCMobile, CBP ACE + ISF 10+2, CBSA ACI + PARS, SAT VUCEM + Carta Porte + CFDI, PHMSA, PAC / container tracking, SendGrid/Twilio, AI routing (OpenAI / Anthropic / Gemini), TestFlight + App Store Connect, GitHub Actions, Azure App Service + MySQL, observability (Datadog/Sentry/CrashOps). Source: wave-1 shard `team_B_agent_5`.

**When you need this.** Before rotating a secret at 2 a.m. Before adding a new region or country. Before calling any external API. Before extending a vendor.

**Cross-links.** Env vars: Appendix A. Landmines: Appendix B. Auth contract to the platform itself: [03_Backend_API_Contract.md](./03_Backend_API_Contract.md). Security posture + rotation cadence: [05_Auth_Security_Compliance.md §17](./05_Auth_Security_Compliance.md).

---

## 1. HERE Maps Platform

iOS speaks to HERE through **two completely different credential sets**; conflating them is the fastest way to leak a key. `EusoTrip.xcconfig` was migrated from apiKey-only to OAuth2 client-credentials on 2026-04-22 after the legacy apiKey was rotated and revoked.

### 1.1 Credential types and env vars

| xcconfig var | Info.plist key | Purpose |
|---|---|---|
| `HERE_USER_ID` | `HEREUserId` | Informational HERE user id (not used in signing). `HERE-7239406a-1b48-45b5-9964-fb81d7a73a7a`. |
| `HERE_CLIENT_ID` | `HEREClientId` | Informational HERE app identifier (not used in signing). `A8wYxsmwZBEqBIud1Jmc`. |
| `HERE_ACCESS_KEY_ID` | `HEREAccessKeyId` | OAuth1.0a consumer key — signs token-exchange requests. |
| `HERE_ACCESS_KEY_SECRET` | `HEREAccessKeySecret` | OAuth1.0a consumer secret — HMAC-SHA256 signing-key material. |
| `HERE_TOKEN_ENDPOINT_URL` | `HERETokenEndpointURL` | `https://account.api.here.com/oauth2/token` |
| `HERE_JS_API_KEY` | `HEREJSApiKey` | HERE Maps JS 3.1 apiKey — used ONLY by Hot Zones heatmap WebView. JS SDK does not accept OAuth Bearer. Minted 2026-04-23 (slot 2 of 2; slot 1 is leaked-pending-revoke NpaQ key). |

Every REST API (Routing v8, Matrix v8, Geocoding & Search v7, Isoline v8, Traffic v7, Maps Tile v3) uses `Authorization: Bearer <token>`. JS bundle rendering Hot Zones WebView uses apiKey — HERE's JS SDK has never supported OAuth.

`HereMapsConfig.plistString` rejects empty strings + unsubstituted `$(...)` placeholders so a fresh SwiftPM test host boots without silently talking to prod with broken creds. `hasBearerCredentials` is sync-safe — SwiftUI's `updateUIView` can call before deciding whether to attach `HereTileOverlay`.

### 1.2 The OAuth1.0a-signed token exchange

`HEREAuthService.exchange()` implements the HERE "app credentials" flow — OAuth2 semantics (`grant_type=client_credentials`, bearer response) wrapped in OAuth1.0a request signature:

1. Collect signing parameters — `(key, value)` pairs containing `grant_type=client_credentials` AND `oauth_*` fields: `oauth_consumer_key, oauth_nonce, oauth_signature_method=HMAC-SHA256, oauth_timestamp, oauth_version=1.0`. The body parameter participates in signature base string even though it only ships in body.
2. Build signature base string: `POST&percentEncode(tokenURL)&percentEncode(sortedEncodedParamString)`. `percentEncode` is RFC3986-strict: allowed set `A-Za-z0-9-._~`, tighter than `URLComponents` defaults. Sort alpha-by-key, then alpha-by-value.
3. Signing key: `percentEncode(keySecret) + "&"`. Client-credentials has no token secret, but trailing `&` is mandatory per OAuth1.0a.
4. HMAC-SHA256 base string with key; base64 the 32-byte MAC.
5. Build `Authorization` header: `OAuth oauth_consumer_key="...",oauth_nonce="...",oauth_signature_method="HMAC-SHA256",oauth_timestamp="...",oauth_version="1.0",oauth_signature="..."`. `grant_type` does NOT appear in Authorization header; only `oauth_*`.
6. POST with `Content-Type: application/x-www-form-urlencoded` and body `grant_type=client_credentials`.
7. Parse response `{ access_token, token_type: "bearer", expires_in: 86399 }`. Expiry ~24h.

Nonces: 16 random bytes hex-encoded (32-char) from `SecRandomCopyBytes`. Timestamps: POSIX seconds.

### 1.3 24-hour bearer cache — memory, Keychain, coalescing

`HEREAuthService` is an **actor**. Three levels:

1. **In-memory** `cached: CachedToken?` — fast path. `isFresh` means >30 minutes life left.
2. **Keychain** — `kSecClassGenericPassword`, service `com.eusorone.eusotrip.hereoauth`, account `bearer`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Survives restarts + cold launches. `saveToKeychain` deletes-then-adds so attribute bag always clean.
3. **In-flight coalescing** — `refreshTask: Task<CachedToken, Error>?`. Concurrent `currentToken()` callers that miss both caches await same `Task` — `/oauth2/token` never sees thundering herd.

Background `prefetchTask` sleeps until 30 min before expiry and refreshes in background — first UI interaction after overnight never pays signing round-trip. On HTTP 401 from downstream REST, client calls `HEREAuthService.shared.invalidate()` (drops memory + Keychain + cancels tasks) and retries exactly once. `HereRoutingClient.authorizedData`, `HereGeocodingClient.authorizedData`, `HereMatrixClient`, `HereTileOverlay.loadTile` all behave this way.

### 1.4 Why JS apiKey can't disappear

Hot Zones heatmap is a WebView loading HERE's `mapsjs-core-3.1`. JS SDK authenticates via `H.service.Platform({ apikey })`. No Bearer flow. Until HERE ships OAuth-for-JS, `HERE_JS_API_KEY` must exist as own credential with own rotation cadence. `HereMapsConfig.jsApiKey` is `nil` when un-provisioned; WebView renders "no credentials" placeholder rather than erroring.

### 1.5 Tile overlay specifics

`HereTileOverlay` extends `MKTileOverlay`. MapKit's `url(forTilePath:)` is URL-only with no header hook, so class overrides `loadTile(at:result:)` instead, attaches `Authorization: Bearer <token>`, hands data back to MapKit. `canReplaceMapContent = true` — Apple basemap fully suppressed for cohesive dark/light registers. URL does NOT carry token in query string — tiles stay cacheable in `URLCache.shared` across token refreshes. Style: `explore.night` or `explore.day` at 400 ppi, 512 px tile edges. When OAuth creds missing, overlay short-circuits to 1×1 transparent PNG — no network error per tile on pan.

---

## 2. Stripe

`routers/payments.ts` is the tRPC layer, wrapped in `safeStripe<T>()` helper returning `null` if `STRIPE_SECRET_KEY` absent or Stripe errors — rest of router degrades to DB-only instead of throwing.

### 2.1 Customer resolution

`resolveStripeCustomerId(ctxUser)` looks up `stripeCustomerId` column in `users` first, falls back to `stripe.customers.list({ email, limit: 1 })` if empty, returns `null` otherwise. Invoice listing (`getInvoices, getReceivables, getReceipts`) always scoped by this — no cross-tenant leakage.

### 2.2 PaymentIntent for checkout

`createPayment` builds Stripe `PaymentIntent`:
- `amount`: `Math.round(parseFloat(input.amount) * 100)` (cents, never float).
- `currency: "usd"`.
- `metadata`: `{ userId, recipientUserId, loadId, paymentType: "load_payment" }`.
- `description`: optional.

Router inserts `payments` row with `status: "pending"` and `stripePaymentIntentId`, emits `emitPaymentSent/emitPaymentReceived` socket events. Client gets `clientSecret + paymentIntentId`; web/iOS confirmation sheet finalizes; Stripe webhook flips row to `succeeded`.

### 2.3 Payment methods

`getPaymentMethods` pulls both `type: "card"` and `type: "us_bank_account"` from `stripe.customers.listPaymentMethods` (Stripe-native ACH via Financial Connections). Default PM from `customer.invoice_settings.default_payment_method`. `setDefaultMethod` updates same field. `deletePaymentMethod` calls `stripe.paymentMethods.detach`.

### 2.4 Refunds

`processRefund` calls `stripe.refunds.create({ payment_intent, amount })`. Amount assumed dollars, multiplied by 100 inside mutation.

### 2.5 Invoice lifecycle

`sendInvoice` → `stripe.invoices.sendInvoice(id)`. Paid invoices read via `status: "paid"` displayed in `getReceipts` alongside `payments` rows. `markInvoicePaid` closes loop for manual out-of-band payments.

### 2.6 Connect flow for carriers

Current `payments.ts` exposes only platform-owned PaymentIntents — **no** `stripe.accounts.create`, `destinationConnectId`, or `application_fee_amount` anywhere. Connect leg (carriers receiving settlements as connected accounts, platform fee skimmed) is **pending implementation**. Canonical shape when it lands:

```ts
stripe.paymentIntents.create({
  amount,
  currency: "usd",
  application_fee_amount,        // platform skim (cents)
  transfer_data: {
    destination: carrier.stripeConnectId,  // acct_xxx
  },
  on_behalf_of: carrier.stripeConnectId,   // for taxes / statement descriptor
  metadata: { loadId, carrierId },
})
```

Carrier's `stripeConnectId` (acct_ prefix) from `stripe.accounts.create({ type: "express", country, email })` during onboarding, with `url` from `stripe.accountLinks.create` presented in-app.

### 2.7 Adaptive Fee engine — the landmine

No persisted `adaptive_fee` schema. Adaptive Fee logic in memory on single Node pod is a landmine:

1. **Slot swaps**: Azure App Service slot swaps (staging → production) drop in-memory state with no replay.
2. **Horizontal scale**: multiple worker pods each compute different fee for same load → race conditions at settlement.
3. **Audit**: regulators + carriers need to reconstruct "why was I charged 7.3% on load 14829?" The answer cannot be "we lost it at last deploy."

**Mitigation**: persist applied fee basis points onto `payments` row at PaymentIntent creation. Back with versioned `fee_schedule` table keyed by effective-at timestamp. Adaptive-Fee overrides write `audit_log` row in same transaction.

---

## 3. Plaid

Plaid is **NOT wired** in shared codebase — grep across `frontend/` finds zero matches. US ACH today runs through Stripe Financial Connections (`type: "us_bank_account"`). If dedicated Plaid becomes necessary (balance checks, income verification), canonical shape:

1. Server mints Link token: `plaidClient.linkTokenCreate({ user: { client_user_id }, products: ["auth"], country_codes: ["US"], language: "en", webhook })`.
2. Client opens Plaid Link, returns `public_token`.
3. Server exchanges: `plaidClient.itemPublicTokenExchange({ public_token })` → `access_token`.
4. Server stores `access_token + item_id` per user (encrypted column, never plaintext).
5. Server calls `plaidClient.authGet({ access_token })` for routing + account numbers → Stripe via `stripe.paymentMethods.create({ type: "us_bank_account", us_bank_account: {...} })`.

Env vars when added: `PLAID_CLIENT_ID, PLAID_SECRET, PLAID_ENV (sandbox|development|production), PLAID_WEBHOOK_URL`.

---

## 4. Apple frameworks

### 4.1 Sign in with Apple

`AuthenticationServices.ASAuthorizationAppleIDProvider`. JWT verified server-side against Apple's JWKS (`https://appleid.apple.com/auth/keys`). Entitlement: `com.apple.developer.applesignin`. Store opaque `sub` claim as `users.appleUserId`.

### 4.2 Apple Pay

Entitlement `com.apple.developer.in-app-payments` + merchant id `merchant.com.eusorone.eusotrip`. `PKPaymentAuthorizationController` collects `PKPayment`; `paymentData` forwarded to Stripe via `stripe.paymentMethods.create({ type: "card", card: { token: "tok_apple_pay_..." } })` or newer `PaymentMethod` flow. Not enabled by default — capability toggle + merchant id in xcconfig.

### 4.3 MapKit fallback

`MKMapView` renders when HERE creds absent or OAuth exchange failing. `HereTileOverlay.canReplaceMapContent` set — when overlay IS attached, Apple basemap hides. Overlay fails to attach → MapKit standard basemap stays visible. Intended graceful degradation.

### 4.4 CoreLocation

`CLLocationManager` with `requestWhenInUseAuthorization` for driver app; `requestAlwaysAuthorization` for background-tracking variant. Significant-location-change monitoring is default background mode — battery-sane. `NSLocationAlwaysAndWhenInUseUsageDescription` must reference HOS compliance + dispatch ETA.

### 4.5 CoreMotion

`CMMotionActivityManager` powers auto-duty-status heuristic: sustained "automotive" > 2 min + GPS speed > 5 mph → driving threshold. Feeds Pulse fatigue detector (micro-sleep accelerometer jerk).

### 4.6 HealthKit (Pulse fatigue detection)

`HKHealthStore` read on `HKQuantityTypeIdentifier.heartRate, heartRateVariabilitySDNN, restingHeartRate`, `HKCategoryTypeIdentifier.sleepAnalysis`. Pulse treats rolling HRV drop + shortened sleep as fatigue signal → "suggest a break" nudge. **No data leaves device without explicit user consent.** Aggregated fatigue scores post to `/pulse/score` over mTLS. Entitlement: `com.apple.developer.healthkit`.

### 4.7 SiriKit / App Intents

`App Intents` (iOS 16+) exposes `StartDriving, EndShift, ReportAccident, LogFuelStop` as donatable actions wrapping existing tRPC mutations. Shortcut phrases bilingual en/es-MX — cross-border markets.

### 4.8 WeatherKit

`WeatherService + WeatherCard + WeatherSnapshot` confirm live. `WeatherKit.shared.weather(for: CLLocation)` called with driver current location; snapshot feeds route-risk overlay (ice / high-wind / flash-flood advisories against HERE polyline). Requires `com.apple.developer.weatherkit` entitlement + WeatherKit subscription in developer account. Free tier: 500,000 calls/month.

---

## 5. ELD providers — canonical integration matrix

`services/eld.ts` is the canonical registry. Every provider shares adapter shape: `{ name, slug, baseUrl, satisfaction, gpsEndpoint, hosEndpoint, authHeader, logoColor, features }`.

| Provider | Slug | Base URL | Auth | GPS endpoint | HOS endpoint |
|---|---|---|---|---|---|
| Samsara | `samsara` | `https://api.samsara.com` | Bearer | `/fleet/vehicles/locations` | `/fleet/drivers/hos/daily-logs` |
| Geotab | `geotab` | `https://my.geotab.com/apiv1` | Bearer | `/Get?typeName=DeviceStatusInfo` | `/Get?typeName=DutyStatusLog` |
| Powerfleet | `powerfleet` | `https://api.powerfleet.com/v1` | Bearer | `/vehicles/locations` | `/drivers/hos` |
| Zonar | `zonar` | `https://api.zonarsystems.net/v3` | Bearer | `/assets/locations` | `/drivers/hours` |
| Motive | `motive` | `https://api.gomotive.com/v2` | Bearer | `/vehicles/locations` | `/drivers/hos_daily_logs` |
| Lytx | `lytx` | `https://api.lytx.com/v2` | Bearer | `/vehicles/positions` | `/drivers/compliance` |
| Netradyne | `netradyne` | `https://api.netradyne.com/v1` | Bearer | `/fleet/vehicles/location` | `/fleet/drivers/hos` |
| Verizon Connect | `verizon_connect` | `https://fim.api.verizonconnect.com/api` | Bearer | `/vehicles/lastknown` | `/hos/status` |
| Azuga | `azuga` | `https://api.azuga.com/v1` | Bearer | `/vehicles/positions` | `/drivers/duty-status` |
| Solera (merged w/ Omnitracs) | `solera` | `https://api.solera.com/fleet/v1` | Bearer | `/vehicles/locations` | `/drivers/hos-logs` |
| Trimble / PeopleNet | `trimble` | `https://api.trimble.com/transportation/v1` | Bearer | `/vehicles/positions` | `/drivers/hours-of-service` |

Aliases in `SLUG_ALIASES`: `keeptruckin → motive`, `omnitracs → solera`, `peoplenet → trimble`, `verizonconnect → verizon_connect`. Exist because DB rows + partner contracts predate rebrands.

### 5.1 Samsara is the primary

`routers/eld.ts` is the hot path. `SAMSARA_API_TOKEN` env required. `samsaraFetch` wraps fetch with 15s `AbortSignal.timeout`, Bearer auth, JSON content type, null-on-error (router degrades to DB counts). Four endpoints consumed:
- `/fleet/vehicles/stats?types=gps` → device inventory for `getSummary`.
- `/fleet/drivers/hos/daily-logs` → historical HOS for `getLogs, getStats`.
- `/fleet/drivers/hos/clocks` → real-time remaining drive/shift/cycle/break for `getDriverStatus`.
- `/fleet/hos/violations` → FMCSA-mapped violations for `getViolations`.
- `/fleet/vehicles/locations` → live GPS for dispatch map.

Router maps Samsara violations to FMCSA cites (`hosDriving → 11-Hour Driving Limit (49 CFR 395.3(a)(3))`) so UI shows regulation, not just string id.

### 5.2 Multi-provider dispatch

`ELDService.loadProvidersForCompany(companyId)` reads `integrationConnections` (per-company API keys), caches 5 min, merges with env-var fallbacks (`MOTIVE_API_KEY / KEEPTRUCKIN_API_KEY, SAMSARA_API_KEY, OMNITRACS_API_KEY`). `eldRouter.connectProvider` upserts per-company credential so carriers don't share env vars with platform.

### 5.3 HOS limits (49 CFR 395) hardcoded in eld.ts

`maxDrivingMinutes=660` (11h), `maxOnDutyMinutes=840` (14h), `breakRequiredAfterMinutes=480` (8h → 30-min), `cycle7DayMinutes=3600` (60h), `cycle8DayMinutes=4200` (70h), `minBreakMinutes=30`, `minOffDutyMinutes=600` (10h).

---

## 6. FMCSA APIs

Two routers: `fmcsa.ts` (QCMobile public REST API) and `fmcsaData.ts` (internal DB-first for Carrier411-equivalent product surface).

### 6.1 QCMobile (live API)

`FMCSA_WEBKEY` env required — `fmcsa.ts` throws on boot if missing (carrier lookup returning fake data is worse than loud failure). Base `https://mobile.fmcsa.dot.gov/qc/services`. webKey is free query parameter; 10s fetch timeout per request.

`lookupByDOT` runs three-layer cache:
1. **Redis `WARM`** (`cacheGet("WARM", "fmcsa:dot:*")`, 24h TTL) — sub-ms, shared across pods.
2. **MySQL persistent cache** (`fmcsaCache.lookupCarrier`) — survives restarts, populated by warm background job.
3. **Live API** — `Promise.allSettled` over four parallel calls: `/carriers/{dot}, /carriers/{dot}/authority, /carriers/{dot}/basics, /carriers/{dot}/cargo-carried`. Response fused in `parseCatalystResponse`, stored in Redis + MySQL.

Parsed shape: `companyProfile, authority` (`allowedToOperate, commonAuthorityStatus`), `safety` (rating, crash totals, OOS counts), `insurance` (BIPD/cargo/bond), `hazmat` (`hazmatFlag`), computed `isBlocked/blockReason` (carriers with `allowedToOperate !== "Y"` hard-blocked from registration), `warnings` array.

`lookupByMC` hits `/carriers/docket/{mc}` for brokers/for-hire. `searchByName` hits `/carriers/name/{name}` URL-encoded, first checking MySQL name cache.

`verifyHMSP` is HMSP permit verifier against 49 CFR 385 Subpart E (Class 1.1/1.2/1.3 explosives, Class 2.3 poison gas, Class 6.1 poison bulk, Class 7 radioactive). Cross-references carrier + cargo-carried → pass/fail/warn checklist registration can block on.

### 6.2 Internal BASICs and materialized view

`fmcsaDataRouter.getSnapshot` tries `carrier_intelligence_mv` (pre-joined MV) before falling back to legacy `getCarrierSnapshot` subquery. MV has `risk_score, risk_tier, eligibility_score, is_blocked` computed — UI hits single row. 30s race-timeout on fallback.

`getSmsScores` reads `fmcsa_sms_scores` (12-run history), returns percentile + alert per BASIC: Unsafe Driving, HOS, Driver Fitness, Controlled Substances, Vehicle Maintenance, Hazmat, Crash Indicator. Empty → `fetchCarrierFromSaferApi` (10s timeout).

`getCrashes, getInspections, getViolations` → `fmcsa_crashes, fmcsa_inspections, fmcsa_violations`. `getInsurance` handles zero-padded DOT quirk (`paddedDot = input.dotNumber.padStart(8, '0')`) — `fmcsa_insurance` uses zero-padded, `carrier` unpadded.

All reads prefer `getReadPool()` (read replica, §17) over `getPool()`.

---

## 7. CBP (US) — ACE + ISF 10+2

`services/eManifest.ts` imported by `crossBorder.ts`:

```ts
import { createACEManifest, createACIManifest, validateACEManifest,
         validateACIManifest, generateACEPayload, generateACIPayload,
         checkFilingDeadline, ACE_PORTS, ACI_PORTS } from "../services/eManifest";
```

**ACE (Automated Commercial Environment)** is US truck e-manifest. `createACEManifest` persists to `aceManifests`, `validateACEManifest` runs business rules (carrier code, shipment/crew/conveyance), `generateACEPayload` serializes to CBP ABI/AMS envelope, `checkFilingDeadline` blocks filings missing "1 hour before arrival" rule.

**ISF 10+2 (Importer Security Filing, 19 CFR 149)** is ocean-cargo pre-arrival filing. Static reference in `services/crossBorderVessel.ts` (`ISF_10_PLUS_2`). `getISFRequirements` returns 10 importer-provided + 2 carrier-provided fields (manufacturer, seller, buyer, ship-to, container stuffing location, consolidator, importer of record, consignee, country of origin, HTS code + vessel stow plan, container status messages).

**What driver sees**: pre-border checklist green only when all docs uploaded (BOL, commercial invoice, packing list, USMCA cert if applicable, driver FAST card / C-TPAT cert, placards for hazmat, Carta Porte if leaving Mexico). `customsDocCount` + eManifest flags (`eManifestsAccepted/Pending/Rejected`) on dashboard aggregate from `documents` filtered by `type LIKE '%manifest%'`.

Live border wait times from `getLiveBorderWaitTimes()` (CBP's public BWT API), cached with `getCacheAgeSeconds`. **No fake-data fallback** — if CBP down, dashboard shows empty state rather than lying.

---

## 8. CBSA (Canada) — ACI + PARS + SARS

ACI (Advance Commercial Information) is CBSA equivalent of ACE. `createACIManifest, validateACIManifest, generateACIPayload, ACI_PORTS` in `services/eManifest.ts` mirror ACE. CBSA eManifest requires 1-hour-pre-arrival for truck highway mode.

**PARS (Pre-Arrival Review System)** — barcode on shipment CBSA scans at booth, pulling electronic shipment record filed by broker. EusoTrip stores `pars_label` document type (`CUSTOMS_DOC_TYPES` includes `pars_label`) + carrier's PARS number; driver sees PNG to affix to cab.

**SARS (Simplified Automated Reporting System)** — express/courier shipments; flagged as future-work doctype.

CBSA requirement metadata: `CBSA_REQUIREMENTS` in `services/canadianCompliance.ts`, plus `PROVINCIAL_WEIGHTS, PROVINCIAL_FUEL_TAX, TDG_CLASSES`. `runFullCanadianComplianceCheck` is single-shot rolling weight, TDG, fuel tax, required-document checks into structured result UI renders as pre-trip greenlight.

---

## 9. SAT (Mexico) — VUCEM + Carta Porte + UUID stamping

`services/cartaPorte.ts`: `createCartaPorte, validateCartaPorte, generateCartaPorteXML`. Carta Porte is Mexican fiscal document for goods transport, CFDI complement mandated by SAT. `generateCartaPorteXML` produces XML envelope; UUID-stamping (timbre fiscal digital) handled by PAC (Proveedor Autorizado de Certificación) — router returns XML; iOS or backend job posts to PAC for UUID.

`services/pedimento.ts`: `createPedimento, validatePedimento, calculatePedimentoTaxes`. Pedimento is Mexican customs declaration; imports AND exports require one.

`services/mexicanDeepDive.ts`: `getVUCEMProcedures, getVUCEMForProduct` — VUCEM (Ventanilla Única de Comercio Exterior Mexicano) is single-window for Mexican foreign trade. Procedures table maps product families to required VUCEM dossier. `getNOMStandards` returns NOM compliance, `getMexicanImportTaxes / estimateMexicanImportTaxes` compute IVA + IEPS + DTA, `getIMMEXPrograms` enumerates maquila exemptions, `getMXBorderCrossings` lists 46 authorized entry/exit points.

Authorized Mexican insurance carriers in `services/mexicanInsurance.ts#AUTHORIZED_INSURERS`. `getRequiredInsurance` picks policy by cargo type + route; `validateMexicanInsurance` cross-checks on-file policy against requirement.

---

## 10. PHMSA (US) — hazmat registration verification

FMCSA router covers HMSP (Hazmat Safety Permit) under §6.2. PHMSA hazmat-carrier registration (annual under 49 CFR 107 Subpart G for carriers + offerors of hazmat-in-commerce) verified indirectly through FMCSA `hazmatFlag === "Y"` + `HMSP_REQUIRED_CLASSES` cross-check (`1.1, 1.2, 1.3, 2.3, 6.1, 7`) computed in `verifyHMSP`. Direct PHMSA API not wired — PHMSA publishes registration lookup as public search page with no REST endpoint. Rely on FMCSA `hazmatFlag` as operational proxy; attach carrier annual registration cert (doc type `dangerous_goods_declaration` or dedicated `phmsa_cert`) as human-verified upload.

---

## 11. PAC / tracking integrations

**Panjiva** — global trade intelligence, bill-of-lading scraping. Used by sourcing product to infer shipper relationships. Not in current crossBorder router but cited in `frontend/server/integrations/_core/registry.ts`.

**Container tracking** — unified through `container_tracking / container_timeline` MCP tools (`mcp__6c5de60a-5b32-4f8d-b10b-9d1b20193d02__container_tracking`). Underlying carriers (MSC, Maersk, CMA CGM, Hapag-Lloyd, ONE, COSCO, Evergreen, Yang Ming) speak via EDI 315 feeds or provider like Project44/FourKites for normalization.

**MarineTraffic / VesselFinder** — AIS-based vessel position feeds. Either vendor exposes JSON API keyed by MMSI or IMO. Treated as interchangeable at service boundary (`getVesselPosition`) — prefer whichever has fresher position. Rate limits force aggregation: one poll per minute per active booking, cached Redis `WARM`.

**Rail interchange** — `services/crossBorderRail.ts` exposes `RAIL_INTERCHANGE_POINTS, RAIL_CREW_CERTS, RAIL_DG_REGULATIONS, getInterchangePoints, checkCrossBorderRailCompliance, estimateRailBorderCrossingTime`. Class-I interchanges (CPKC at Eagle Pass/Laredo/International Falls, UP/BNSF hand-offs) are reference data. Real-time car locations from rail carriers' own APIs (CP ShipView, BNSF Car Management) and AAR RailInc where contracted.

---

## 12. SendGrid / Twilio

**SendGrid** — transactional email provider. Env `SENDGRID_API_KEY`. Notification service (`services/notificationService.ts`) fans out for: load-assigned, payment-received, dispute-opened, ELD-violation-alert, invoice-sent. Templates under `EusoTrip/*` template family; handle collisions via `template_id` pinning per env.

**Twilio** — SMS + voice. Env `TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER`. Primary: driver OTP login, dispatch alerts, 2FA fallback (SMS weakest factor — preferred TOTP). Voice rarely — only accident-response escalation. All SMS via template approval table with opt-out keyword map (`STOP, QUIT, UNSUBSCRIBE`). Auto-enforces A2P 10DLC for US numbers.

---

## 13. OpenAI / Anthropic / Google Gemini — ESANG AI routing

ESANG (Eusorone Semantic Agent Network for Goods) is AI orchestration layer. Routing by call type:

| Workload | Model | Rationale |
|---|---|---|
| Chat + multi-turn dispatch assistant | `claude-opus-4 / claude-sonnet-4` | Long-context tool use, conservative on JSON |
| Structured extraction (BOL, invoice, POD OCR) | `gpt-4o + gpt-4o-mini` | Vision + JSON mode, lowest cost |
| Background summarization | `gemini-1.5-flash` | Fastest, cheapest for volume |
| Embedding (load search, carrier search) | `text-embedding-3-large` (OpenAI) | Best recall@10 on eval |
| Policy/safety classification (driver moderation) | `gpt-4o-mini` | Built-in content policy |
| Agentic planning (ESANG Planner, Lane assignment) | `claude-sonnet-4 / gpt-4o` | A/B routed by priority |

Env: `OPENAI_API_KEY, ANTHROPIC_API_KEY, GOOGLE_GENERATIVE_AI_API_KEY`. Each has soft rate limit via Redis token-bucket.

### 13.1 iOS streaming

Consumes AI via SSE from tRPC subscription layer. Each provider's native streaming (Anthropic `stream: true`, OpenAI `stream: true`, Gemini `streamGenerateContent`) adapted into uniform `ESANGEvent` type — `{ type: "delta" | "tool_call" | "done", payload }` — iOS has one parser regardless of model. Back-pressure: if SSE buffer fills, backend drops deltas (not tool calls or done events) rather than OOMing.

---

## 14. Apple TestFlight / App Store Connect API

**TestFlight** — `xcrun altool --upload-app --type ios` or modern `xcrun notarytool + altool` pair. Reviewer comms via App Store Connect "What to Test" + TestFlight app feedback button.

**App Store Connect API** — JWT-signed REST at `https://api.appstoreconnect.apple.com/v1/`. Env: `ASC_KEY_ID, ASC_ISSUER_ID, ASC_P8_KEY_BASE64`. Used by CI for:
- `POST /v1/betaAppReviewSubmissions` — submit build for beta review.
- `POST /v1/betaGroups/{id}/relationships/builds` — attach build to internal group.
- `POST /v1/appStoreVersionSubmissions` — production submission.
- `GET /v1/builds?filter[app]=...&sort=-uploadedDate` — track upload.

JWTs: ES256, 20-min max lifetime, cached in-memory on CI worker — don't re-sign every call.

---

## 15. GitHub Actions — deploy pipeline to Azure

Canonical workflow (`.github/workflows/deploy.yml`):

1. `on: push` to `main`, `workflow_dispatch` for manual.
2. `jobs.build`: `actions/checkout@v4`, `actions/setup-node@v4` (node 20), `npm ci`, `npm run build`, `npm run test`. Artifacts: bundled `frontend/dist + frontend/server/dist`.
3. `jobs.deploy-staging`: `azure/login@v2` with `AZURE_CREDENTIALS` (service-principal JSON), `azure/webapps-deploy@v3` with `slot-name: staging` and `package: ./dist.zip`.
4. `jobs.smoke`: curl staging `/healthz`, run Playwright smoke against staging.
5. `jobs.swap`: `az webapp deployment slot swap` promoting staging → production. Requires `production-approvers` environment review.

Secrets in `production` env: `AZURE_CREDENTIALS, STRIPE_SECRET_KEY, SAMSARA_API_TOKEN, FMCSA_WEBKEY, SENDGRID_API_KEY, TWILIO_AUTH_TOKEN, OPENAI_API_KEY, ANTHROPIC_API_KEY, GOOGLE_GENERATIVE_AI_API_KEY, DATADOG_API_KEY, SENTRY_AUTH_TOKEN, ASC_P8_KEY_BASE64`.

---

## 16. Azure App Service — slot swapping + WEBSITE_RUN_FROM_PACKAGE

EusoTrip runs Azure App Service (Linux, Node 20). Two slots: `staging` and `production`.

Slot-sticky (per slot): `NODE_ENV, APP_ENV=production/staging, STRIPE_SECRET_KEY` (live vs test), `DATADOG_ENV, SENTRY_ENV`.

Non-sticky (follow code): `OPENAI_API_KEY, ANTHROPIC_API_KEY`, vendor keys same across envs.

**Slot swap**: atomic from load balancer's view — pre-warmed staging slot switched to production VIP. Warm-up endpoint `GET /healthz?warmup=1` pre-opens MySQL pool, pre-fetches HERE OAuth token, pre-warms Redis. If warm-up fails, swap aborted, old production stays live.

**`WEBSITE_RUN_FROM_PACKAGE = 1`**. Deployed zip mounted read-only; App Service boots from it directly. Upsides: faster cold start, no concurrent-write corruption, immutable deploys. Downside: app can't write to own install dir — temp files to `/tmp` or `%TEMP%`, long-lived to Azure Storage or MySQL. Why HERE OAuth cache lives in iOS Keychain (client) + Redis (server), never on disk.

---

## 17. Azure MySQL — pool + replicas

Primary: Azure Database for MySQL Flexible Server, 8 vCore General Purpose. Via `mysql2/promise`, pool size `(max_connections / worker_count) * 0.8`. Pool exposed via `getPool()` in `frontend/server/db/index.ts`; `getReadPool()` returns read-replica pool if `DATABASE_READ_URL` configured, falls back to primary.

`fmcsaData.ts` + every read-heavy router (`fmcsaDataRouter.getSnapshot, getSmsScores, getCrashes, getInspections, getViolations, getInsurance, getAuthority`) prefer `getReadPool()` — FMCSA tables are the biggest rows in warehouse (millions of inspection records) and Carrier Monitor product dominates read workload.

Every pool query wrapped in `safeQuery(pool, sql, params, timeoutMs)` — `Promise.race` against `setTimeout` rejection so hung replica can't hang tRPC past 30s limit.

Env: `DATABASE_URL` (writer), `DATABASE_READ_URL` (reader). Both TLS (`ssl: { rejectUnauthorized: true }`). Azure AD auth as rotation-friendly alternative to password auth; target Q3 2026.

---

## 18. Observability — Datadog / Sentry / CrashOps

**Datadog** — APM + log ingestion. `dd-trace` auto-instruments Express/tRPC/MySQL2. Env: `DD_API_KEY, DD_SITE=datadoghq.com, DD_ENV, DD_SERVICE=eusotrip-api, DD_VERSION={git.sha}`. Custom metrics: `stripe.paymentintent.create.latency_ms, here.oauth.refresh.count, samsara.fetch.failure.rate, fmcsa.cache.hit_rate, eld.provider.configured.count`.

**Sentry** — error monitoring. `@sentry/node` on API, `@sentry/swift` on iOS. Env: `SENTRY_DSN, SENTRY_ENV, SENTRY_RELEASE={git.sha}`. Source maps uploaded in CI via `sentry-cli releases new && sentry-cli releases files upload-sourcemaps`. iOS dSYMs via `sentry-cli debug-files upload` during archive.

**CrashOps** — iOS-specific crash reporter. Not strictly necessary given Sentry Swift SDK captures signal crashes, but CrashOps rollout-aware dashboards materially better for "did this Tokens build crash more than prior?" If adopted: `CRASHOPS_API_KEY` in xcconfig, `CrashOpsClient.configure(apiKey:)` in `AppDelegate.didFinishLaunching`.

**Recommended SLOs:**
- iOS: crash-free sessions ≥ 99.7% P30.
- API: 95p tRPC latency < 300 ms; 99p < 900 ms.
- HERE OAuth: 99.99% exchange success (less triggers page).
- FMCSA lookup: 95p warm-cache < 10 ms; 95p cold < 2.5 s.
- Samsara fetch error rate: < 0.5% rolling 24h.
- Stripe PaymentIntent success: > 99.5% (excluding 4xx user errors).

---

## Appendix A — Complete env-var inventory

| Var | Owner | Purpose |
|---|---|---|
| `HERE_USER_ID` | iOS xcconfig | Informational |
| `HERE_CLIENT_ID` | iOS xcconfig | Informational |
| `HERE_ACCESS_KEY_ID` | iOS xcconfig | OAuth1.0a consumer key |
| `HERE_ACCESS_KEY_SECRET` | iOS xcconfig | OAuth1.0a consumer secret |
| `HERE_TOKEN_ENDPOINT_URL` | iOS xcconfig | `/oauth2/token` |
| `HERE_JS_API_KEY` | iOS xcconfig | JS SDK (Hot Zones heatmap) |
| `STRIPE_SECRET_KEY` | backend | Stripe REST |
| `STRIPE_WEBHOOK_SECRET` | backend | Webhook signature verification |
| `SAMSARA_API_TOKEN` | backend | Samsara Bearer |
| `MOTIVE_API_KEY / KEEPTRUCKIN_API_KEY` | backend | Motive Bearer |
| `OMNITRACS_API_KEY` | backend | Omnitracs/Solera Bearer |
| `FMCSA_WEBKEY` | backend | QCMobile webKey |
| `SENDGRID_API_KEY` | backend | SendGrid |
| `TWILIO_ACCOUNT_SID` | backend | Twilio |
| `TWILIO_AUTH_TOKEN` | backend | Twilio |
| `TWILIO_FROM_NUMBER` | backend | Twilio sender |
| `OPENAI_API_KEY` | backend | ESANG routing |
| `ANTHROPIC_API_KEY` | backend | ESANG routing |
| `GOOGLE_GENERATIVE_AI_API_KEY` | backend | ESANG routing |
| `DATABASE_URL` | backend | Azure MySQL writer |
| `DATABASE_READ_URL` | backend | Azure MySQL reader |
| `REDIS_URL` | backend | Redis WARM cache |
| `DD_API_KEY` | backend | Datadog |
| `SENTRY_DSN` | backend + iOS | Sentry |
| `ASC_KEY_ID / ASC_ISSUER_ID / ASC_P8_KEY_BASE64` | CI | App Store Connect |
| `AZURE_CREDENTIALS` | CI | SP JSON for azure/login |
| `PLAID_CLIENT_ID / PLAID_SECRET / PLAID_ENV / PLAID_WEBHOOK_URL` | backend (future) | Plaid Link when enabled |

---

## Appendix B — Known landmines

1. **Adaptive Fee in memory, not persisted.** See §2.7. Write fee basis points onto `payments` row at PaymentIntent creation. No exceptions.
2. **JS apiKey separate from Bearer OAuth.** Rotation runbook must rotate both. Legacy NpaQ apiKey still pending revoke at HERE portal — close ticket.
3. **FMCSA insurance DOT padding.** `fmcsa_insurance` uses zero-padded DOTs, `carrier` unpadded. `getInsurance` queries both; don't "fix" one without other.
4. **`WEBSITE_RUN_FROM_PACKAGE=1` means read-only install dir.** Any new code writing next to bundle silently fails in production.
5. **Samsara token rate limits are per-org, not per-API-key.** Multi-tenant carriers sharing single platform token get 429s. Migrate to per-company `integrationConnections` rows before large fleets.
6. **HERE OAuth token is 24h but `isFresh` uses 30-minute safety margin.** Don't tighten — prefetch task relies on it to avoid race conditions at boundary.
7. **CBP BWT API has no fallback.** Deliberate. Don't add one; fake wait times cost carrier a missed dock slot.
8. **Stripe `application_fee_amount` is in cents.** In-memory Adaptive Fee produces percentages. Conversion explicit, rounded with `Math.round`, not `Math.floor`.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
