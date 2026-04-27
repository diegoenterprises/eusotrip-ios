# 03 · Backend API Contract

**What this covers.** The canonical end-to-end network surface of EusoTrip — tRPC routers, transport, codec, auth, procedure catalog, middleware chain, error envelope, rate limits, versioning, idempotency, and real-time transport (Socket.IO, push, WCSession, polling fallback, offline resilience, latency budgets, deep linking, NWPathMonitor). Merges wave-1 shards `team_B_agent_1` (API contract) and `team_B_agent_2` (WebSocket + realtime).

**When you need this.** Before wiring a new screen to the backend. Before designing a new procedure. Before debugging an auth regression. Before adding a new real-time surface. Before changing a shared DTO.

**Cross-links.** Tenancy and schema: [04_Database_and_Schema.md](./04_Database_and_Schema.md). Auth internals: [05_Auth_Security_Compliance.md](./05_Auth_Security_Compliance.md). External vendors: [06_Third_Party_Integrations.md](./06_Third_Party_Integrations.md). Web parity: [91_Web_Mobile_Parity.md](./91_Web_Mobile_Parity.md).

---

## 1. Backend Stack Overview

Node.js 20 monolith on Azure App Service, public hostname `eusotrip-app.azurewebsites.net`. Express 4.21 HTTP layer mounts a single tRPC 11.6.x handler at `/api/trpc`. Every request from iOS, Pulse (watchOS), and web client hits the same Express process — no separate mobile API gateway. Business logic under `frontend/server/routers/*.ts` (273 files), shared plumbing `frontend/server/_core/*`, Drizzle schema `frontend/drizzle/schema.ts`, service adapters `frontend/server/services/*`.

Persistence: MySQL 8.x (Azure Flexible Server) via Drizzle ORM (`drizzle-orm@0.36.x` with `mysql2`). Migrations in `frontend/drizzle/migrations/*.sql`. `getDb()` dynamically imported inside every procedure body to avoid cold-start penalties. No ORM-level connection pooling — MySQL driver's internal pool (default 10).

tRPC server initialised with `superjson` transformer (`trpc.ts:72`). iOS passes plain JSON under `json` key only; server's superjson decoder is tolerant of bare `json`-only payload.

**Secondary infrastructure.**
- **Cache**: no Redis. `lightspeedCache` middleware declared in `_core/trpc.ts:448` but runs passthrough unless routers install it. Azure App Service ephemeral in-process `Map`. Second ephemeral `Map` in `_core/rateLimiting.ts:22` for rate-limit counters.
- **Auth**: bespoke JWT via `_core/auth.ts:authService.createSessionToken`, signed `HS256` with `JWT_SECRET`. Cookie name `eusotrip_token` from `@shared/const`. Options in `_core/cookies.ts:getSessionCookieOptions` — `httpOnly: true`, `sameSite: 'lax'`, `secure: true` in prod, `path: '/'`, `maxAge: 365 days`.
- **Email**: `_core/email.ts` via SendGrid. Verification tokens in `users.metadata`.
- **SMS / 2FA**: `services/mfa.ts` (TOTP via `speakeasy`) with SMS-backed legacy fallback in `services/notifications.ts`.
- **WebSockets**: `_core/websocket.ts` (46KB) — Socket.IO 4.x. Rooms keyed `conversation:<id>`, `load:<id>`, `tenant:<id>`. iOS does not currently subscribe.
- **External integrations**: Stripe, Plaid (via `routers/wallet.ts`), HaulPay (`integrations/haulpay/router.ts`), FMCSA, Samsara/Motive/Geotab (via `services/eld.ts`).
- **AI layer**: ESANG on Google Gemini via `_core/esangAI.ts` (178KB, 4500+ lines).

No separate Node worker tier. Background jobs run inline (`.catch(() => {})` fire-and-forget) or via cron outside tRPC critical path.

---

## 2. Transport + Codec

**Transport**: HTTPS over Azure managed TLS. All traffic terminates at `eusotrip-app.azurewebsites.net`. No custom CDN, no Cloudflare, no API Management front.

**Wire format**: tRPC v11 HTTP adapter.
```
POST /api/trpc/<router>.<procedure>
GET  /api/trpc/<router>.<procedure>?input=<URL-encoded JSON>
```

Swift client (`EusoTripAPI.swift:300–366`) uses GET for queries, POST for mutations. For GET, input is JSON-encoded then passed as raw value of `URLQueryItem(name: "input", value: ...)`. Load-bearing — comment lines 311–317 notes pre-percent-encoding the JSON caused `Unexpected token '%'` errors in the prod Driver Intel news feed.

**Request envelope**: `{ "json": <payload> }`.

**Response envelope success**: `{ "result": { "data": { "json": <payload> } } }`.

**Response envelope error** (tRPC v11 nested shape):
```json
{
  "error": {
    "json": {
      "message": "...",
      "code": -32001,
      "data": {
        "code": "UNAUTHORIZED",
        "httpStatus": 401,
        "path": "hos.getStatus"
      }
    }
  }
}
```
Earlier Swift mirrored a v9/v10 shape without the nested `json` — every tRPC error came through as fallback literal "Request failed" ("Can't reach news feed · Request failed"). v11 nested envelope is now matched verbatim.

**Codec**: superjson server, plain `JSONEncoder`/`JSONDecoder` iOS. Works because iOS never sends/receives `Date`, `BigInt`, `Map`, or other non-JSON-safe values directly — timestamps round-trip as ISO-8601 strings or epoch doubles.

**Auth carrier**: `eusotrip_token` cookie is primary. Bearer header is belt-and-braces fallback (`EusoTripAPI.swift:329`). Backend middleware reads cookie first, `Authorization: Bearer <jwt>` second. iOS uses `HTTPCookieStorage.shared` wired through `URLSessionConfiguration.httpCookieStorage`. Snapshot-restore pair (`authCookieSnapshotJSON` / `restoreAuthCookiesFromJSON`) forces session cookies to +1-year expiry for cold-launch survival.

**Content-Type**: `application/json` both directions. No multipart; image uploads go through `messages.uploadAttachment` as base64 data URLs.

---

## 3. Complete `lazy var` roster on `EusoTripAPI.shared`

### Primary router clients (27, `MainActor`-isolated)

| # | Lazy var | Type | Line | Backend namespace |
|---|---|---|---|---|
| 1 | `loads` | `LoadsAPI` | 250 | `loads` |
| 2 | `hos` | `HOSAPI` | 251 | `hos` |
| 3 | `auth` | `AuthAPI` | 252 | `auth` |
| 4 | `registration` | `RegistrationAPI` | 253 | `registration` |
| 5 | `inspections` | `InspectionsAPI` | 254 | `inspections` |
| 6 | `esang` | `ESangAPI` | 255 | `esang` |
| 7 | `wallet` | `WalletAPI` | 256 | `wallet` |
| 8 | `loadLifecycle` | `LoadLifecycleAPI` | 257 | `loadLifecycle` |
| 9 | `bayOps` | `BayOpsAPI` | 258 | `bayOps.*` (4 sub-wizards) |
| 10 | `notifications` | `NotificationsAPI` | 259 | `notifications` + `push` |
| 11 | `drivers` | `DriversAPI` | 260 | `drivers` |
| 12 | `news` | `NewsAPI` | 261 | `news` |
| 13 | `messaging` | `MessagingAPI` | 262 | `messages` (Swift `messaging`→backend `messages`) |
| 14 | `hotZones` | `HotZonesAPI` | 263 | `hotZones` |
| 15 | `eld` | `ELDAPI` | 264 | `eld` |
| 16 | `walletExtras` | `WalletExtrasAPI` | 285 | `wallet`, `earnings` |
| 17 | `factoring` | `FactoringAPI` | 286 | `factoring` |
| 18 | `tax` | `TaxAPI` | 287 | derived from `earnings.*` |
| 19 | `rewards` | `RewardsAPI` | 288 | `rewards` |
| 20 | `gamification` | `GamificationAPI` | 289 | `gamification` |
| 21 | `fleetCanonical` | `FleetCanonicalAPI` | 290 | `fleet.getVehicles` |
| 22 | `zeunMechanics` | `ZeunMechanicsAPI` | 291 | `zeunMechanics` |
| 23 | `fleet` | `FleetAPI` | 292 | `fleet.*Mobile` |
| 24 | `profile` | `ProfileAPI` | 293 | `profile` |
| 25 | `loyalty` | `LoyaltyAPI` | 294 | `loyalty` (legacy) |
| 26 | `earnings` | `EarningsAPI` | 295 | `earnings` |
| 27 | `settlementBatching` | `SettlementBatchingAPI` | 296 | `settlementBatching` |

### BayOps sub-lazies (4 × 6 = 24 paths)

Each of `{backingAssist, discharge, connectHose, disconnect}` exposes: `start / advanceStep / recordEvidence / complete / abort / getSession`.

### Deprecated struct bodies (no lazy var backing)

- `FuelCardAPI` (2616) — `fuelCardRouter` never existed → use `fleet.getFuelTransactionsMobile`.
- `AchievementsAPI` (2730) → `gamification.*`.
- `LeaderboardAPI` (3119) → `gamification.getLeaderboard`.
- `AvailabilityAPI` (3281) — not yet shipped.
- `RoomsAPI` (3365) — no presence surface.
- `ZeunDriverAPI` (3432) — wrong proc name → `zeunMechanics.getMyBreakdowns`.

All six tagged `@available(*, deprecated, message: "...")`, zero live call-sites.

---

## 4. Procedure-to-DB-Table Matrix

`ctx.user.id` and `ctx.user.companyId` threaded through `isolationMiddleware` for every isolated procedure — implicit in every DB query.

### auth (inline in routers.ts:325–907)

- `auth.login` `{ email, password, twoFactorCode? }` → `{ success, user, requiresTwoFactor?, method? }` (users, mfaTokens).
- `auth.me` → `AuthUser?` (users).
- `auth.logout` → `{ success: true }` (clears cookie).
- `auth.verifyEmail` `{ token }`, `auth.resendVerification`, `auth.forgotPassword`, `auth.resetPassword`.
- `auth.refreshToken`, `auth.checkSession`, `auth.revokeAllSessions`.
- `auth.setup` (TOTP QR), `auth.enable`, `auth.disable`, `auth.regenerateBackupCodes`.
- `auth.changePassword`, `auth.get2FAStatus`.

### registration (registrationRouter:1203)

Seven role flavors: `registerDriver`, `registerShipper`, `registerCatalyst`, `registerBroker`, `registerDispatch`, `registerEscort` + verify/resend.

### hos (hosRouter:934)

- `hos.getStatus` → `HOSStatus`.
- `hos.getCurrentStatus` `{ driverId? }` → `HOSCurrentStatus`.
- `hos.changeStatus` `{ status, source, lat?, lon?, location, odometer?, remark?, loadId?, ts }` → `HOSChangeStatusResult` (hos_logs, hos_daily_summary, audit_logs).
- `hos.getDailyLog` `{ date?, driverId? }` → `HOSDailyLog`.
- `hos.getLogHistory` `{ days, driverId? }` → `[HOSDailyLog]`.
- `hos.certifyLog` `{ date, signature }` (hos_daily_summary.certifiedAt, certifiedSignature).
- `hos.addRemark` `{ text, entryId? }` (hos_logs.remark).
- `hos.getViolations` → `[HOSViolation]`.

### loads (loadsRouter:921)

- `loads.search` `{ query?, status?, cargoType?, limit }` → `[LoadSummary]`.
- `loads.getById` `{ id: Int }` → `Load`.

### inspections (inspectionsRouter:931)

- `inspections.getTemplate` `{ type }`, `inspections.submit`, `inspections.getHistory`, `inspections.getPrevious`, `inspections.getOpenDefects`.
- DVIR forms: `inspections.createDVIR` (dvir_reports, dvir_defects), `inspections.getDVIRHistory`, `inspections.getDVIRCategories` (static from 49 CFR 396.11(a)(1)).

### esang (esangRouter:1185)

- `esang.chat` `{ message, context?: { currentPage?, loadId? } }` → `{ message, suggestions?, actions? }`.
- `esang.clearHistory`.

### wallet (walletRouter:1082)

- `wallet.createPlaidLinkToken` → `PlaidLinkToken`.
- `wallet.exchangePlaidPublicToken` `{ publicToken, institution? }` → `PlaidLinkedAccount`.
- `wallet.createStripeSetupIntent` → `{ clientSecret, publishableKey }`.
- `wallet.attachStripePaymentMethod` `{ paymentMethodId }`.
- `wallet.getBalance` → `WalletBalance`.
- `wallet.getInstantPayoutEligibility` → `InstantPayoutEligibility`.
- `wallet.getTransactions` `{ limit, offset }` → bare `[TxnRow]`.
- `wallet.getPayoutMethods` → bare `[PayoutMethodRow]`.

### loadLifecycle (loadLifecycleRouter:1407)

- `loadLifecycle.executeTransition` `{ loadId, transitionId, location?, targetLocation?, complianceChecks? }` → `ExecuteTransitionResponse`. Backed by 169KB state machine.

### bayOps (4 wizards × 6 paths)

Inputs and outputs documented above. Persisted to `bayOpsSessions`, `bayOpsEvents`.

### drivers (driversRouter:1001 also aliased as `driver:` line 1576)

- `drivers.acceptLoad`, `drivers.declineLoad`, `drivers.counterOffer`, `drivers.getPendingLoads`, `drivers.getActiveTender`, `drivers.getRateConURL`.

### news (newsRouter:1221)

- `news.getArticles`, `news.cacheStatus`, `news.getTrending`, `news.getMorningBrief`, `news.getBreakingNews`, `news.saveArticle`, `news.unsaveArticle`, `news.getSavedArticles`.

### messages (messagesRouter:976, Swift exposes as `messaging`)

- `messages.getConversations`, `messages.getMessages`, `messages.sendMessage`, `messages.markAsRead`, `messages.getUnreadCount`, `messages.search`, `messages.searchUsers`, `messages.createConversation`, `messages.deleteConversation`, `messages.archiveConversation`, `messages.uploadAttachment`, `messages.sendPayment`, `messages.unsendMessage`, `messages.getUserPhone`.

### hotZones (hotZonesRouter:1371)

- `hotZones.getRateFeed` `{ equipment? }` → `HotZonesFeedResult`.

### eld (eldRouter:1269)

- `eld.getAllProviders`, `eld.getConnectionStatus`, `eld.getProviderConfig`, `eld.connectProvider`, `eld.disconnectProvider`.

### earnings (earningsRouter:958)

- `earnings.getWeeklySummaries`, `earnings.getSummary`, `earnings.getYTDSummary`, `earnings.getEarnings`.

### factoring (factoringRouter:1149)

- `factoring.getOffer` `{ loadId: Int }` → `{ offerId, grossAmount, feeBps, feeAmount, netAmount, eligible, reason? }`.
- `factoring.accept` `{ loadId, offerId }`.

### tax (no canonical `tax.*` namespace)

- `tax.get1099` — MISSING on backend. `taxReportingRouter` exists but admin-only.
- `TaxAPI.getSummary(year)` calls `earnings.getYTDSummary` and computes tax locally at 25.31%.

### rewards (rewardsRouter:1290)

- `rewards.getCatalog`, `rewards.getHistory`, `rewards.redeem`.

### gamification (gamificationRouter:1170)

- `gamification.getMissions`, `gamification.startMission`, `gamification.claimMissionReward`, `gamification.getProfile`, `gamification.getLeaderboard`, `gamification.getRewardsCatalog`, `gamification.getBadges`.

### fleet (fleetRouter:961 — both canonical and `Mobile` wrappers)

- `fleet.getVehicles`, `fleet.listAssets`, `fleet.getAsset`, `fleet.getMaintenanceScheduleMobile`, `fleet.getFuelTransactionsMobile`.

### profile (profileRouter:1076)

- `profile.listReferrals`, `profile.getReferralCode`, `profile.getReputation`.

### settlementBatching (settlementBatchingRouter:1049)

- `settlementBatching.getDriverBatchView` `{ driverId: Int }`.

### zeunMechanics (zeunMechanicsRouter:1326)

- `zeunMechanics.getMyBreakdowns` `{ limit, offset, status }`.

**Total distinct iOS-referenced procedure paths: ~130.** Of those, 6 deprecated paths return 404 but are unreachable from current call-sites.

---

## 5. Auth Contract

### JWT issuance
1. iOS POSTs `auth.login` with `{ email, password, twoFactorCode? }`.
2. Backend validates bcrypt hash, checks MFA (TOTP via `mfaService.verifyLogin`, fallback SMS OTP in `users.metadata.twoFactorCode`).
3. On success, `ctx.res.cookie(COOKIE_NAME, token, { ...options, maxAge: 365 * 24 * 60 * 60 * 1000 })`.
4. JWT HS256 signed with `JWT_SECRET`. Claims: `{ id, email, role, name, companyId, iat, exp }`. Expiry 7 days; refresh via `auth.refreshToken`.

### iOS storage
- **Primary**: `HTTPCookieStorage.shared` via `URLSessionConfiguration.httpCookieStorage`.
- **Keychain snapshot**: `EusoTripAPI.authCookieSnapshotJSON()` extracts auth cookies (`token`, `auth_token`, `session`, `next-auth.session-token`, `__Secure-next-auth.session-token`) to JSON blob. `EusoTripSession` writes to Keychain service `com.eusorone.eusotrip.auth` with shared access group `group.com.eusorone.eusotrip`. Dates ISO-8601.
- **Rehydration**: `EusoTripSession.bootstrap()` reads Keychain blob, calls `restoreAuthCookiesFromJSON(_:)`. Forces `expiresDate = now + 1 year` to sidestep Session-scoped cookie loss.
- **Bearer fallback**: after receiving `Set-Cookie: token=...`, iOS copies value into `self.authToken`, sent as `Authorization: Bearer <jwt>`.

### Invalidation

| Trigger | Effect |
|---|---|
| `auth.logout` | `clearCookie(COOKIE_NAME)`. iOS calls `clearCookies()`. |
| `auth.revokeAllSessions` | Bumps `users.metadata.tokenVersion`. Middleware rejects stale JWTs. |
| `auth.resetPassword` | Same tokenVersion bump. |
| 7-day expiry | iOS sees `UNAUTHORIZED` → `.unauthenticated` → login screen. |

See [05_Auth_Security_Compliance.md](./05_Auth_Security_Compliance.md) for full session/MFA/RBAC/isolation policy.

---

## 6. Middleware Chain

### Base
- `publicProcedure = t.procedure` (line 76) — no auth.
- `protectedProcedure = t.procedure.use(requireUser)` (line 97) — throws `UNAUTHORIZED` if absent.

### RBAC — 24 canonical roles

**Trucking (12)**: `SUPER_ADMIN, ADMIN, SHIPPER, CATALYST, BROKER, DRIVER, DISPATCH, ESCORT, TERMINAL_MANAGER, FACTORING, COMPLIANCE_OFFICER, SAFETY_MANAGER`.
**Rail (6)**: `RAIL_SHIPPER, RAIL_CATALYST, RAIL_DISPATCHER, RAIL_ENGINEER, RAIL_CONDUCTOR, RAIL_BROKER`.
**Vessel (6)**: `VESSEL_SHIPPER, VESSEL_OPERATOR, PORT_MASTER, SHIP_CAPTAIN, VESSEL_BROKER, CUSTOMS_BROKER`.

`roleProcedure(...allowed)` composes `requireUser + hasRoleAccess`. `SUPER_ADMIN`/`ADMIN` inherit via `ROLE_HIERARCHY`.

Factory aliases: `adminProcedure`, `superAdminProcedure`, `driverProcedure`, `catalystProcedure`, `shipperProcedure`, `brokerProcedure`, `dispatchProcedure`, `escortProcedure`, `terminalProcedure`, `factoringProcedure`, `complianceProcedure`, `safetyProcedure`, `shipperCatalystProcedure`, `operationsProcedure` (SHIPPER|CATALYST|BROKER|DISPATCH), `complianceSafetyProcedure`, rail/vessel mirrors.

### Transport mode gates
- `truckProcedure = requireUser + requireTruckMode`
- `railProcedure = requireUser + requireRailMode`
- `vesselProcedure = requireUser + requireVesselMode`

### Approval gate (`approvedProcedure:268`)
`requireApproval` reads `users.metadata.approvalStatus`. Non-admins rejected FORBIDDEN until approved. Used on loads/bids/wallet/billing/ESANG. iOS surfaces full-screen "Pending Approval" gate.

### Data isolation (`isolationMiddleware:378`)
Computes `{ userId, role, companyId, scope: 'OWN' | 'COMPANY' | 'TENANT', tenantId, linkedCompanies[] }` attached as `ctx.isolation`. Application-level RLS substitute — every isolated router ANDs `WHERE companyId = ctx.isolation.companyId`.

### Composed
- `isolatedProcedure = requireUser + isolationMiddleware + autoAudit`
- `isolatedApprovedProcedure = requireUser + requireApproval + isolationMiddleware + autoAudit`
- `isolatedRoleProcedure(...roles)` + twelve role-specific variants.

### Audit (`autoAudit:276`)
Every call recorded non-blockingly to `audit_logs`. Mutations → `DATA_WRITE`, queries → `DATA_READ`, errors → `API_ERROR` (severity HIGH for FORBIDDEN, MEDIUM otherwise). Captures `procedure, type, durationMs, userRole, errorCode, errorMessage` (first 200 chars). SOC 2 CC6.2/CC6.3/CC7.1.

### Lightspeed cache (line 448)
Declared but passthrough. Routers opt in via `require('../middleware/lightspeedCache').buildLightspeedCacheMiddleware(t)` for 10–60s per-router TTLs.

---

## 7. Error Contract

### HTTP status codes

| Status | Cause | iOS mapping |
|---|---|---|
| 200 | Success | `TRPCResult<T>.result.data.json` |
| 200 + error envelope | tRPC v11 can do this | Error first, `.trpcError` / `.unauthenticated` |
| 400 | Zod validation | `trpcError(message)` |
| 401 | `UNAUTHORIZED` | `.unauthenticated` |
| 403 | `FORBIDDEN` | `.unauthenticated` (UI doesn't distinguish yet) |
| 404 | Missing procedure | `httpStatus(404, body)` |
| 429 | Rate limit | `httpStatus(429, body)` — no auto-retry |
| 500 | `INTERNAL_SERVER_ERROR` | `trpcError(message)` or raw 500 |

### iOS decoding pattern
1. Decode `TRPCErrorEnvelope` FIRST.
2. If successful: promote `UNAUTHORIZED`/`FORBIDDEN`/401/403 to `.unauthenticated`, else throw `.trpcError`.
3. Else if `statusCode ∈ {401, 403}`: throw `.unauthenticated`.
4. Else if `statusCode ∉ 200..300`: throw `.httpStatus(code, body)`.
5. Else decode `TRPCResult<Output>`, return `.result.data.json`.
6. Decode failure: `.decodingFailed(String(describing: error))`.

Envelope-first decode is critical because tRPC v11 returns 200 with error payload for INTERNAL_SERVER_ERROR thrown after headers started.

---

## 8. Rate Limiting

Enforced at Express layer, not tRPC. Source: `_core/rateLimiting.ts` (166 lines). Keyed by user-id if authenticated, else IP.

| Limiter | Window | Max | Attach |
|---|---|---|---|
| `apiRateLimiter` | 60s | 100 | Catch-all `/api/*` |
| `authRateLimiter` | 15min | 10 | `auth.login`, `auth.forgotPassword` |
| `uploadRateLimiter` | 60min | 50 | `messages.uploadAttachment` |
| `webhookRateLimiter` | 60s | 1000 | Stripe/Plaid/HaulPay webhooks |
| `mfaRateLimiter` | 5min | 5 | `auth.enable`, `auth.disable`, TOTP verify |
| `registrationRateLimiter` | 60min | 3 | `registration.register*` |
| `passwordResetRateLimiter` | 15min | 3 | `auth.forgotPassword`, `auth.resetPassword` |

Store: `Map<string, {count, resetTime}>` in-process, cleaned every 60s. **NOT shared across Azure App Service instances** — effective limit is `maxRequests × instanceCount`. Planned hardening: Redis.

Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After` (429 only). iOS does not currently read headers — retry-with-backoff is roadmap.

---

## 9. Versioning

tRPC has no built-in version field. Strategy:

1. **Namespace + procedure is the version.** Adding fields is additive. Adding required fields is breaking — pattern: add optional + default server-side.
2. **Breaking changes ship as new procedures.** `fleet.getMaintenanceScheduleMobile`, `fleet.getFuelTransactionsMobile` are examples.
3. **Singular-plural aliases** (lines 1573–1579): `driver`=`drivers`, `catalyst`=`catalysts`, `broker`=`brokers`, `escort`=`escorts`, `shipper`=`shippers`, `terminal`=`terminals`. iOS uses plural canonical.
4. **Deprecation flow**: server keeps procedure live, returns `deprecation: { replacement, sunset }` field in response envelope. iOS logs warning.
5. **Feature flags** in `featuresRouter`: `features.get(flag)` → `{ enabled, variant }`.
6. **Drizzle migrations**: forward-compatible, new columns NULLable with defaults. iOS DTOs declare newer fields as Optional.

No `X-EusoTrip-API-Version` header yet. tRPC endpoint is effectively v11-ish tied to deployed Azure slot commit SHA.

---

## 10. Idempotency — ULID keys from iOS

iOS does NOT currently attach idempotency keys at the transport layer. Known gap. De-facto contract:

1. **State-machine guards**: `loadLifecycle.executeTransition` rejects duplicate transition with `{ success: false, error: 'Already in target state', step: 'from_state_check' }`. Server checks current `loads.status` vs transition's `from`. iOS retries safe — replay is no-op.
2. **Wizard sessions**: `bayOps.*.start` keyed on `(loadId, kind)`. Re-start returns existing session. `advanceStep` keyed on `(loadId, kind, toStep)`.
3. **Messages**: `messages.createConversation` idempotent for 1:1 DMs (lookup by sorted participant IDs). `messages.sendMessage` has no idempotency key — retry creates duplicate.
4. **Wallet**: `wallet.attachStripePaymentMethod` idempotent via `INSERT IGNORE` on `stripe_payment_method_id`. `factoring.accept(loadId, offerId)` gated on `factoringOffers.status != 'accepted'`.
5. **HOS**: `hos.changeStatus` deduplicates on `(driverId, ts, status)` within 10 seconds.

### Planned ULID pattern
iOS generates ULID at mutation-call site (`ulid-swift`), writes to Core Data `OfflineQueue`, includes as top-level `idempotencyKey` sibling to `json`:
```json
{ "json": {...}, "idempotencyKey": "01HKXXX..." }
```
Server middleware (`idempotencyMiddleware`, not yet shipped) persists `(userId, procedure, idempotencyKey, responseJson)` with 24h TTL. Short-circuits duplicates by replaying cached response.

Today, closest: `sync.*` namespace (`syncRouter:1442`) used by Pulse only.

---

## 11. WebSocket + Realtime — Current State

The backend is **Socket.IO v4**, not tRPC subscriptions. Confirmed: `createWSHandler`, `applyWSSHandler`, `wsLink`, `TRPCSubscription`, `observable(`, `text/event-stream` all return **zero matches**.

What exists: Socket.IO server bound to HTTP listener at `path: "/ws"`, implemented in two files:

- **`frontend/server/services/socketService.ts`** (1,303 lines) — production singleton. Reads JWT from `handshake.auth.token`, verifies against `JWT_SECRET`. Attaches `@socket.io/redis-adapter` if `REDIS_URL`/`AZURE_REDIS_URL` set for multi-instance fan-out. Exports typed emitters: `emitLoadStateChange`, `emitTimerEvent`, `emitApprovalEvent`, `emitUserNotification`, `emitCarrierSafetyChange`, `emitLoadBoardUpdate`, `emitETLProgress`, `emitDataRefreshed`, `broadcastSafetyIncident`, `notifyDocumentExpiry`, `broadcastFuelSurchargeUpdate`.
- **`frontend/server/socket/index.ts`** (383 lines) — partially-redundant stub with own `initializeSocket()`, connected-user map, broader catalogue (emergency, bids, terminal, dispatch, gamification, escort, zeun breakdown, geofence, presence). Predates `socketService.ts`. Consolidation is recommended.

### Rooms (union of both files)

`user:<id>`, `role:<ROLE>` (case inconsistency — flagged), `company:<id>`, `fleet:<id>`, `load:<id>`, `convoy:<id>`, `conversation:<id>`, `terminal:<id>`, `carrier:<dot>`, `loadboard:global`, `rail:shipment:<id>`, `rail:yard:<id>`, `vessel:booking:<id>`, `vessel:container:<id>`, `vessel:port:<id>`, `intermodal:shipment:<id>`.

### iOS real-time client

**One file**: `EusoTrip/Services/RealtimeService.swift`. The only place in Swift using `URLSessionWebSocketTask`. Speaks Socket.IO v4 wire subset manually:
- `40<JSON>` engine-io MESSAGE + socket-io CONNECT
- `42<JSON>` server EVENT
- `41` server DISCONNECT
- `2` / `3` ping / pong

Reconnection: exponential backoff capped at 30s (1, 2, 4, 8, 16, 30, 30…). JWT passed both as `?token=` and `Authorization: Bearer …` (covers cold `HTTPCookieStorage`). On receipt, frames translate into `NotificationCenter` posts (`.esangRefreshSurface`, `.esangOpenMeDetail`, `.eusoMessageReceived`, `.eusoConvoyInbound`). Listen-heavy — decodes server events but only emits small outbound set (`load:join`, `load:leave`, `conversation:join`, `conversation:leave`).

---

## 12. What Should Be Real-Time

| Surface | Producer | Room | Event |
|---|---|---|---|
| Dispatch board (broker → carrier) | `dispatch.ts` | `user:<carrierId>`, `company:<carrierCompany>` | `LOAD_ASSIGNED`, `load:stateChange` |
| HOS clock ticking | iOS local `HOSLiveStore` (authoritative); server mirror via `HOS_WARNING` | `user:<driverId>` | `HOS_WARNING`, `hos:clock:tick` (proposed) |
| Messages | `messages.ts send` mutation | `conversation:<id>` | `message:new` |
| SOS acknowledgment | Company dispatch + safety | `company:<id>`, `role:SAFETY_MANAGER`, `role:DISPATCH` | `emergency:alert`, `emergency:ack` (proposed) |
| Load status | `loadLifecycle.ts` | `load:<id>`, `role:dispatch` | `load:stateChange`, `LOAD_STATE_CHANGED`, `LOAD_POD_SUBMITTED` |
| Leaderboard | `gamification.ts` | `user:<id>` + `company:<id>` | `gamification:reward_claimed`, `leaderboard:delta` (proposed) |
| ESANG streaming | `esangVoiceOrchestrator` | per-socket | `voice:delta`, `voice:complete` |
| Convoy envelopes (F13) | `escort:convoy_envelope` | `convoy:<id>` | `escort:convoy_envelope` |
| Bids | `loadBidding.ts` | `load:<id>`, `role:DISPATCH`, `role:BROKER` | `bid:received` |
| FSC rate changes | `fscEngine.ts` cron | global | `fsc:rate:updated` |

**Gaps**: no `leaderboard:delta` today. No `emergency:ack` reverse channel. HOS has server `HOS_WARNING` but no authoritative per-tick mirror (device is source of truth).

---

## 13. APNs Configuration

**Push is FCM-fronted, not direct APNs.** From `services/notificationService.ts:470–575`:

1. Backend reads `FIREBASE_SERVICE_ACCOUNT` JSON, initializes `firebase-admin` singleton.
2. Active rows in `pushTokens` (`userId`, `isActive = true`).
3. `admin.messaging.Message` with platform blocks:
   - iOS: `apns.payload.aps = { sound, badge:1, "content-available":1 }`, `sound: "critical"` for `priority === "urgent"` (requires **Critical Alert** entitlement).
   - Android: `android: { priority, notification: { channelId, sound } }`.
4. On `not-registered`/`invalid-argument`/`invalid-registration-token`, token flipped `isActive = false`.
5. `lastUsedAt` updated on success.

`push` router exposes five procedures but **does not expose a first-class `registerDevice` mutation** (zero matches for `registerDevice`). iOS `PushService.swift` uses two-step workaround:
1. `UNUserNotificationCenter.requestAuthorization([.alert, .badge, .sound, .provisional])`.
2. `UIApplication.shared.registerForRemoteNotifications()`.
3. In `didRegister(deviceToken:)`, hex-encode token, call `notifications.updatePreferences(channel:"push", category:"loads"/"safety"/"system", enabled:true)` three times. Token captured server-side from `x-push-token` header.

**Load-bearing workaround** — must be replaced by real `push.registerDevice({ token, platform, appVersion, bundleId })` mutation.

Topics are not APNs topics. What backend calls "categories" (`loads, bids, payments, messages, missions, promotions, compliance, safety, dispatch, billing, system`) are server-side routing labels against `notificationPreferences`, checked before `sendToPushChannel` fires.

---

## 14. Watch Push via WCSession

Pulse does not have its own APNs. All phone→watch flows via `WCSession`.

Files:
- iOS: `WatchCommandHandler.swift`, `WatchAuthBridge.swift`, `ConvoyPhoneBridge.swift`, `EusoTripApp+WatchBridge.swift`.
- Watch: `EusoTrip Pulse Watch App/WatchConnectivityManager.swift`, legacy `EusoTrip Watch App/WatchConnectivityManager.swift`.

Flow: Socket.IO frame on iPhone → `RealtimeService.dispatch(event:payload:)` posts NotificationCenter → bridge (e.g., `ConvoyPhoneBridge`) forwards to watch via `WCSession.default.sendMessage(_:replyHandler:errorHandler:)` (foreground-reachable) or `transferUserInfo(_:)` (guaranteed). Convoy: phone is pure pass-through — ships opaque signed bytes with op `"convoy.ingest"`; watch verifies P-256 signature before mutating. Phone never decodes or trusts convoy envelopes.

Latency: `sendMessage` 50–200ms. `transferUserInfo` batched up to 30s. SOS acks + convoy envelopes prefer `sendMessage` with `transferUserInfo` fallback.

---

## 15. Polling Fallback Inventory

Three cohorts:

**One-shot `.task { await refresh() }`**: `010_DriverHome.swift`, `025_Paperwork.swift`, `052_RateconTender.swift`, `053_ESangDispatchChat.swift`, `056_DriverProfile.swift`, `057_DriverVehicleCard.swift`, `058_DriverWeeklyPlan.swift`, `059_DriverTripsHistory.swift`, `060_TheHaulDashboard.swift`, `068_MeEarnings.swift`, `MeDetailScreens.swift`, `IntroSplash.swift`, `DriverConversationView.swift`.

**Timed polling**: `HOSLiveStore.swift` (on-device 1 Hz, server 30s), `HotZonesWidget.swift` (60s), `ELDIntegrationStore.swift` (15s during shift), `LiveDataStores.swift` (30s dispatch/load board), `DynamicStore.swift` (20s leaderboard).

**Hybrid**: `DriverConversationView.swift` (listens + reconciles 60s), `061_TheHaulMissions.swift` (listens + 120s).

Views missing live updates would benefit from Socket.IO room subscription — staleness from "until manual pull" to sub-second.

---

## 16. Proposed Upgrade Path

**Short term (1–2 sprints):** codify event catalogue as shared TS+Swift contract from single zod schema. Generate `RealtimeEvents.swift`. Add missing emitters (`leaderboard:delta`, `hos:clock:mirror`, `emergency:ack`).

**Mid term:** optional — add `@trpc/server createWSHandler` alongside Socket.IO on separate path (`/trpc-ws`) for subscription-shaped procedures (`load.watchStatus`, `hos.watchClock`, `messages.watchThread`, `dispatch.watchBoard`). iOS would add `wsLink`. Optional — Socket.IO already works with Redis fan-out.

**Long term:** consolidate `socket/index.ts` into `services/socketService.ts`. Move toward single typed emit surface.

---

## 17. Offline Resilience

**Pending-mutation queue**: every state-changing mutation (POD submit, DVIR submit, HOS duty change, message send, bid place, SOS file) wrapped with persistence adapter writing `{ idempotencyKey, procedureName, input, attemptCount, nextRetryAt }` to SQLite before firing. Success → deleted. Transient failure → survives, retried by background Task on NWPathMonitor `satisfied` transition.

**Exponential retry**: 1s, 2s, 4s, 8s, 16s, 32s, 60s ceiling. Abandon after 24h with user-visible banner.

**Idempotency**: UUIDv7 `clientId` per mutation. Server dedupes on `(userId, clientId)` — not universal today, risk area.

**Conflict resolution by domain**:
- **LWW (server wins)**: load assignment, broker acceptance, carrier tier, compliance, payroll.
- **CRDT (driver wins)**: HOS duty log (FMCSA legal record), POD signature capture, offline DVIR, messages drafted offline.
- **OT / vector-clock ordering**: ESANG chat threads.
- **G-Counter CRDT**: leaderboard deltas.
- **Mesh-relayed**: convoy state via `MeshRelay.swift` when cell down.

See [60_Offline_First_and_Pulse_Watch.md](./60_Offline_First_and_Pulse_Watch.md) for the F01–F16 offline system.

---

## 18. Latency Budgets Per Surface

| Surface | Budget | Path |
|---|---|---|
| Wallet balance open | < 800 ms | `wallet.getOverview` cold; cache-warm < 150 ms |
| Load board first page | < 1.2 s | `loadBoard.list` Redis cache, 20-row chunk |
| HOS clock tick | < 100 ms on-device | Local `HOSLiveStore` 1 Hz Timer |
| Push delivery end-to-end | < 5 s p95 | Backend emit → FCM → APNs → device |
| Socket message fan-out | < 500 ms p95 | Single-instance; Redis adapter ~20 ms |
| Watch mirror of phone state | < 300 ms | `WCSession.sendMessage` when reachable |
| SOS ack visible on phone | < 3 s | Phone fires mutation, server emits `emergency:ack` to `user:<id>` |
| ESANG first audio chunk | < 800 ms TTFA | `voice:init` → `voice:delta` |
| Dispatch board assignment toast | < 1.5 s | `LOAD_ASSIGNED` → NotificationCenter → view refresh |

SLO violations logged as XCGlobalEvents via telemetry router.

---

## 19. Performance Instrumentation

`telemetry.ts` router (17 KB) is ingest for client metrics. OSLog partial coverage: `MeDetailScreens.swift`, `OrbLog.swift`, `HOSStatus.swift`.

**Signposts to add** (`os_signpost` category "realtime"):
- `RealtimeService.openOnce` begin/end
- `RealtimeService.handleFrame` begin/end — tagged with event name
- `PushService.bootstrap` begin/end
- `WatchCommandHandler.process` begin/end
- tRPC call boundary in `EusoTripAPI` per procedure name (`async_call`)

**MetricKit**: `MXMetricManagerSubscriber` in `EusoTripApp` for daily `MXMetricPayload` rollups (hangs, disk writes, cellular, launch time). Diagnostics surface crashes + hangs. Ship to telemetry router on launch (max 1×/day): `telemetry.submitMetricKit({ payload })`.

**XCGlobalEvents** (ad-hoc event stream):
```swift
api.telemetry.event(name: "ws.reconnect", attrs: ["attempt": retryAttempt, "reason": reason])
```

Server router batches into ClickHouse / Postgres `telemetry_events`.

---

## 20. NWPathMonitor for Connection State

Five files already use it: `EusoTrip Pulse Watch App/EusoTripWatchApp.swift`, `OfflineQueue.swift`, `OrbStateMachine.swift`, `SatellitePhoneBridge.swift`, `SatelliteFallback.swift`.

**Phone app currently has NWPathMonitor only in `SatellitePhoneBridge`, not as general-purpose singleton.**

Recommendation: create `EusoTrip/Services/NetworkMonitor.swift` with `@MainActor` singleton exposing `@Published var status: NWPath.Status` and `@Published var isExpensive: Bool`. Subscribers:

- `RealtimeService` → on `.satisfied` re-enter `runConnectionLoop`; on `.unsatisfied` cancel reads.
- `PendingMutationQueue` → on `.satisfied` flush.
- `PushService` → on first `.satisfied` after denied, re-attempt `registerForRemoteNotifications()`.
- UI → banner "Offline · changes will sync" bound to `status != .satisfied`.
- Data stores with timers → pause polling on `.unsatisfied`, resume + immediate refresh on `.satisfied`.

Expensive-path: when `isExpensive == true` (cellular, hotspot), polling 3× slower; high-res telemetry to 1-minute batching.

---

## 21. Deep-Link + Universal Links on Push Open

iOS push payloads from FCM include `data.type` and `apns.payload.aps`. Missing uniform **deep-link contract**.

**Proposed FCM `data` map fields**:
```json
{
  "type": "load.assigned",
  "deeplink": "eusotrip://load/12345",
  "universal": "https://eusotrip.com/load/12345",
  "loadId": "12345",
  "conversationId": "98"
}
```

**iOS handling**:
1. `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)` reads `userInfo["deeplink"]` and `userInfo["universal"]`.
2. Single `DeepLinkRouter` actor resolves to `Destination` enum (`.load(id)`, `.conversation(id)`, `.hosWarning`, `.sos(incidentId)`, `.leaderboard`, `.wallet`).
3. Router `@Published var pending: Destination?`. `ContentView` observes and performs programmatic `NavigationPath.append(...)`.
4. Universal Links: `apple-app-site-association` at `https://eusotrip.com/.well-known/apple-app-site-association` with paths `/load/*`, `/message/*`, `/wallet`, `/haul/*`. `Associated Domains` entitlement with `applinks:eusotrip.com`.
5. Cold-start: `launchOptions[.remoteNotification]` carries payload — process after auth bootstrap (stash in `DeepLinkRouter.pending` during boot, flush after `AuthStore.status == .signedIn`).

**Silent-push** (`content-available:1`): use for prefetch. If `type == "load.assigned"`, background `loads.get(id)` so load cached before user opens app 10 seconds later. Reduces perceived open-latency to sub-400ms on warm launch.

**Watch deep-link parity**: `WKExtensionDelegate.handleUserActivity(_:)` fires on tap with `userInfo`. Watch `DeepLinkRouter` mirrors phone's — same enum, same destinations — so watch jumps straight into Orb, SOS, or HOS detail.

---

## 22. Summary of Key Findings + Priority Actions

**Findings:**
1. No tRPC subscriptions exist — real-time is pure Socket.IO v4, dual-implemented.
2. iOS has exactly one WebSocket client (`RealtimeService.swift`) speaking Socket.IO protocol manually via `URLSessionWebSocketTask`. Works but fragile.
3. Push is FCM-wrapped APNs with no dedicated `push.registerDevice` — workaround via preferences + header.
4. Polling is pervasive across driver screens; many `.task { await refresh() }` sites would benefit from Socket.IO room subscription.
5. Offline resilience uneven — watch has `OfflineQueue`, phone has no equivalent singleton.
6. NWPathMonitor partial — present on watch and satellite bridge but not as phone-wide singleton.
7. Deep-link routing from push is ad-hoc — needs uniform `DeepLinkRouter` + Universal Links AASA.
8. Conflict resolution: LWW for server-authoritative, CRDT for driver-authored HOS/DVIR/messages, G-Counter for leaderboards.
9. Latency budgets achievable — gap is measurement, not capability.

**Priority actions next sprint:**
- Ship `push.registerDevice` mutation + drop header workaround.
- Create `NetworkMonitor` singleton on phone.
- Create `PendingMutationQueue` on phone (mirror watch's `OfflineQueue`).
- Codify event catalogue as shared TS+Swift contract.
- Consolidate `socket/index.ts` into `services/socketService.ts`.
- Add `DeepLinkRouter` + AASA file.
- Instrument `RealtimeService` + `PushService` with `os_signpost`.

---

## Appendix — Quick Counts

- **Distinct tRPC namespaces mounted** in `appRouter`: 273 top-level keys, 251 unique routers.
- **Distinct procedures iOS can call**: ~130 live + 6 deprecated = 136 referenced.
- **DB tables touched from iOS-reachable paths**: ~85.
- **Role procedures exported**: 24 role-specific + 12 isolated + 11 audited = 47 procedure factories.
- **Lazy var router clients on `EusoTripAPI.shared`**: 27 primary + 4 BayOps = 31.
- **Deprecated struct bodies awaiting physical deletion**: 6.
- **Error envelope shapes supported by iOS**: 1 (v11 nested `error.json.*`); legacy shapes purged 2026-01.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
