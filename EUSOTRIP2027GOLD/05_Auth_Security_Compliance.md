# 05 · Auth, Security, Compliance, and Privacy

**What this covers.** Authentication, session lifecycle, MFA (three parallel), 24-role RBAC, multi-tenant isolation, registration, deep-link reset flows, Pulse watch auth, transport security, PII handling, GDPR / CCPA / US-state privacy, SOC 2 audit trail, HIPAA flag, hazmat data access rules, PCI-DSS scope reduction, secrets management + rotation, known vulnerabilities (including three P0s), vulnerability disclosure program.

**When you need this.** Before touching auth code. Before adding a role or permission. Before a SOC 2 audit. Before an external security reviewer walks in. Before shipping a change that touches PII or money.

**Cross-links.** Middleware + isolation: [03_Backend_API_Contract.md §6](./03_Backend_API_Contract.md). Schema + tenancy: [04_Database_and_Schema.md](./04_Database_and_Schema.md). Launch runbook + incident: [92_Launch_Runbook_and_Rollback.md](./92_Launch_Runbook_and_Rollback.md).

This document is the authoritative posture for Wave 1 of the Eusorone / EusoTrip platform. It binds together the iOS client (`EusoTrip/Services/EusoTripSession.swift`), the paired Apple Watch (`EusoTrip Pulse Watch App/AuthStore.swift`), and the tRPC server surface (`frontend/server/routers.ts`, `frontend/server/routers/registration.ts`, `frontend/server/_core/trpc.ts`). Written so the next engineer — or the next external auditor — can pick it up cold and understand what is enforced, what is aspirational, and what is broken.

---

## 1. Authentication flow — credentials → JWT → Keychain

Canonical sign-in is initiated from iOS via `EusoTripSession.signIn(email:password:twoFactorCode:)`. Calls `auth.login`, a `publicProcedure` at `routers.ts:350`. Accepts `{ email, password, twoFactorCode? }`.

Server-side:
1. `authService.loginWithCredentials(email, password)` verifies bcrypt hash (cost 12) in `users.passwordHash`. Mismatch → `"Invalid credentials"`.
2. MFA in two layers — TOTP via `mfaService.isEnabled(userId)` against `mfaTokens` table, then legacy SMS 2FA in `users.metadata.twoFactorEnabled`. If enabled + no code → `{ success: false, requiresTwoFactor: true, method: "totp" | "sms" }` without issuing session.
3. On full success, JWT minted by `authService`, written as HttpOnly cookie via `ctx.res.cookie(COOKIE_NAME, result.token, { ...cookieOptions, maxAge: 365 * 24 * 60 * 60 * 1000 })`. `getSessionCookieOptions(ctx.req)` centralizes Secure / SameSite / domain rules.

iOS `EusoTripSession` persists bearer AND a snapshot of server-issued `Set-Cookie` payload to Keychain via `EusoKeychain`:
- `kAuthToken` — bearer string, `Authorization: Bearer` header on every tRPC call.
- `kAuthCookies` — JSON-encoded cookie snapshot (name, value, domain, path, secure, httpOnly, expires) so cold launches can rehydrate `HTTPCookieStorage.shared` before first `/auth.me`. Without this, session-scoped cookie evaporates on app restart and user is 401'd despite valid bearer.
- `kCachedUser` — JSON `AuthUser` snapshot, enabling app to boot straight into `.signedIn` instead of flashing `SignIn`.

Keychain written with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (survives OS updates and reinstalls on iOS 10.3+). Access group `$(AppIdentifierPrefix)com.app.eusotrip.shared`, team prefix resolved at runtime by probing throwaway generic-password item. Shared across iPhone + Pulse targets — removes WCSession as single-transport SPOF for watch pairing.

---

## 2. Session lifecycle — TTL, refresh, invalidation, force sign-out

- **Access JWT TTL.** Cookie minted `maxAge: 365 * 24 * 60 * 60 * 1000` — **one year**. Dramatically longer than OWASP 15-minute recommendation. Justification: driver UX — can't re-auth mid-long-haul; watch companion would lose orb identity. **Doctrine call**: conscious risk acceptance for Wave 1. Must shorten to 15-min access + 30-day refresh once refresh endpoint wired to iOS.
- **Refresh.** `refreshTokens` module exists under `services/security/auth/` but **NOT invoked by iOS**. `EusoTripSession` treats `/auth.me` as refresh probe: successful response snapshots rotating cookies back to keychain (`api.authCookieSnapshotJSON()` lines 115–117). Sliding-expiry rotation by proxy. Fragile — needs explicit refresh grants.
- **Invalidation.** `auth.logout` clears cookie server-side (`ctx.res.clearCookie(COOKIE_NAME, { ...cookieOptions, maxAge: -1 })`). iOS wipes `kAuthToken, kAuthCookies, kCachedUser, kUnauthStrikes`. Watch notified via `WatchAuthBridge.shared.clear()`.
- **Force sign-out.** No global session-revocation list. `auth.revokeAllSessions` is **a no-op** (SKILL.md §16) — returns `{ success: true }` without terminating sessions. Compromised admin only rotatable by password reset, which does not invalidate minted JWTs. **Single most urgent session-layer vulnerability.**
- **401 debounce.** iOS requires **two consecutive** `/auth.me` UNAUTHORIZED responses before tearing down local state (`kUnauthStrikes` counter lines 124–149). Intent: absorb cookie-jar rehydrate races + cold-start middleware blips. Side effect: real revocation takes two cycles to propagate.

---

## 3. Multi-Factor Authentication — three parallel surfaces

Three parallel MFA implementations, a compliance and phishing-surface liability:

1. **Legacy SMS 2FA.** Inline in `routers.ts:387–415`. Secrets in `users.metadata.twoFactorCode` and `users.metadata.twoFactorCodeExpiry` as **plaintext strings** inside JSON blob on users row. Rate limit 5 per code (line 400), 10-min expiry, cleared on success. Plaintext storage fails SOC 2 CC6.1 — must be deprecated.

2. **Current TOTP.** Three separate service files: `services/mfa.ts`, `mfaService.ts`, `services/security/auth/mfa.ts`. Canonical: `mfaService.setupTOTP(userId, email)`, `mfaService.verifySetup(userId, code)`, `mfaService.verifyLogin(userId, code)`. Secrets AES-256-GCM encrypted at rest (`mfa.ts:15`). Issuer `EusoTrip`, 6-digit codes, 30-sec period, ±1-period skew (`mfaService.ts:23–25`). Backup codes SHA-256-hashed via `hashBackupCodes`.

3. **Passwordless / magic link.** Email-only sign-in in `services/security/auth/index.ts`. Limited iOS wiring; primarily shipper onboarding.

**Doctrine recommendation.** Consolidate to TOTP + WebAuthn passkey. Retire SMS 2FA in Wave 2 (SIM-swap, plaintext-at-rest). Retire magic-link once passkey adoption clears 60%. The three-implementation fan-out is a direct audit finding.

---

## 4. RBAC — 24-role enum, procedure helpers, Action×Resource×Scope

Canonical role enum from `_core/trpc.ts`:

```
TRUCKING (12): SUPER_ADMIN, ADMIN, SHIPPER, CATALYST, BROKER, DRIVER,
               DISPATCH, ESCORT, TERMINAL_MANAGER, FACTORING,
               COMPLIANCE_OFFICER, SAFETY_MANAGER
RAIL (6):      RAIL_SHIPPER, RAIL_CATALYST, RAIL_DISPATCHER,
               RAIL_ENGINEER, RAIL_CONDUCTOR, RAIL_BROKER
VESSEL (6):    VESSEL_SHIPPER, VESSEL_OPERATOR, PORT_MASTER,
               SHIP_CAPTAIN, VESSEL_BROKER, CUSTOMS_BROKER
```

24 roles. `SUPER_ADMIN` inherits all; `ADMIN` inherits all except `SUPER_ADMIN`. Hierarchy in `hasRoleAccess()`.

**Procedure helpers.** `roleProcedure(...allowed)` factory wraps middleware that (a) throws `UNAUTHORIZED` on missing `ctx.user`, (b) calls `hasRoleAccess`, (c) emits `RBAC_VIOLATION` via `auditSecurity()` on failure, (d) throws `FORBIDDEN`.

Pre-built: `adminProcedure`, `superAdminProcedure`, `driverProcedure`, `shipperProcedure`, `catalystProcedure`, `brokerProcedure`, `dispatchProcedure`, `escortProcedure`, `terminalProcedure`, `factoringProcedure`, `complianceProcedure`, `safetyProcedure`, all rail/vessel variants, + multi-role aggregates: `shipperCatalystProcedure`, `operationsProcedure` (shipper+catalyst+broker+dispatch), `complianceSafetyProcedure`.

**Audited variants.** Every role procedure has an `audited*` sibling chaining `autoAudit` middleware — every call recorded with `DATA_READ` (queries) or `DATA_WRITE` (mutations), including `userRole`, `durationMs`, error severity.

**Action×Resource×Scope primitives.** Placeholder types exist — `Action` enum (READ, WRITE, APPROVE, DELETE, EXPORT), `Resource` enum (LOAD, BID, WALLET, DRIVER, DOCUMENT, …), `Scope` enum (OWN, COMPANY, TENANT, GLOBAL) — but permission-resolution layer is **NOT wired** to tRPC procedures. Today: pure role-check. Staged for Wave 2 where every procedure declares `@requires({ action, resource, scope })` and middleware resolves against computed permission set. Until shipped, RBAC is coarse: `BROKER` has access to every broker-shaped endpoint regardless of whether bid belongs to their company.

**`driverProcedure` vs `adminProcedure`.** `driverProcedure = roleProcedure(ROLES.DRIVER)` — pure role match. `adminProcedure = roleProcedure(ROLES.ADMIN, ROLES.SUPER_ADMIN)`. Neither enforces company scope — that's the isolation layer.

---

## 5. Multi-tenant isolation — companyId, tenantId, isolationMiddleware

`isolationMiddleware` (in `_core/trpc.ts`) lazily loads `middleware/rls-context.ts` and computes:

```
ctx.isolation = { userId, companyId, scope, linkedCompanies[] }
```

`scope`: `OWN | COMPANY | TENANT | GLOBAL`. Routers filter every SELECT by `ctx.isolation.companyId` (or linked-companies for broker/factoring). `isolatedProcedure` chains `requireUser → isolationMiddleware → autoAudit`. `isolatedApprovedProcedure` also requires approved status. Isolated role procedures for every role.

**What breaks without isolation.** A `catalystProcedure` omitting `.where(eq(loads.companyId, ctx.isolation.companyId))` returns every load in the database. Not hypothetical — 157K-line `loads.ts` router must be grep-audited for unscoped queries. Isolation filter must be applied inside procedure body, not assumed.

**Bypass risks:**
- Routers using `protectedProcedure` or `roleProcedure` directly (instead of `isolatedProcedure` / `isolatedRoleProcedure`) have `ctx.user` but NOT `ctx.isolation` — authors must manually scope. Every such call site is a bypass candidate.
- `SUPER_ADMIN`/`ADMIN` deliberately skip approval gate (`requireApproval`, `_core/trpc.ts:220–224`). If isolation keys off same short-circuit, admins may see cross-tenant. Current code does NOT short-circuit isolation for admins, but individual routers sometimes do — any `if (ctx.user.role === 'ADMIN') return allData` branch is a finding.
- `tenantId` tracked on companies for white-label. Routers joining only on `companyId` but serving multiple tenants leak across tenants.

---

## 6. Registration — seven role-specific + admin + verification

`routers/registration.ts` (2186 lines) defines distinct `auditedPublicProcedure` mutations:

1. `registerShipper` — EIN, address, PHMSA, EPA ID, insurance (general liability + pollution), hazmat classes, state permits, products.
2. `registerCatalyst` — USDOT, MCN, fleet size (power units, trailers, drivers), hazmat endorsement, hazmat authority, tanker endorsement, liability + cargo insurance.
3. `registerBroker` — MC number, surety bond, trust fund details.
4. `registerDriver` — CDL number, endorsements, medical card expiry, home state, operating states.
5. `registerDispatch` — company linkage, responsibilities, driver count.
6. `registerEscort` — pilot-car certifications, state authorizations, equipment.
7. `registerCarrier` — tied to Catalyst shape for fleet carriers.

Plus: `registerSafetyManager, registerComplianceOfficer, registerTerminalManager, registerFactoring, registerAdmin`.

**Shared post-registration path.** Every registration calls `storeRegistrationMetadata()` (lines 64–115), serializing role-specific payload to `users.metadata` JSON with `approvalStatus: "pending_review"` default. Fans out to `seedUserOperatingStates(), initNewUserGamification(), sendPostRegistrationNotifications(), autoCreateProductProfiles()`. All `.catch(() => {})` — never blocks registration. Correct UX, silent degradation risk on first run.

**Email verification.** `sendPostRegistrationNotifications()` generates token via `emailService.generateVerificationToken(email, userId)`, merges into metadata (`verificationToken, verificationExpiry`), fires email + SMS via `notifyRegistration()`. `verifyEmail` (line 1571) consumes — currently using `users.openId` as verification UUID, a shortcut that should be dedicated single-use token with TTL. Once verified, `users.isVerified = true`.

**Phone verification.** Piggy-backs on SMS leg of `notifyRegistration`. Codes in metadata; verification flips `users.phoneVerified`.

---

## 7. Deep-link reset password — `eusotrip://reset?token=<uuid>`

`forgotPassword` and `resetPassword` live in `routers/users.ts` (around 1800–1880).

- **Request.** `forgotPassword(email)` looks up user, generates UUID reset token, inserts `password_reset_tokens (id, userId, token, expiresAt, usedAt)`, emails deep link `eusotrip://reset?token=<uuid>` + fallback HTTPS URL for web. Email always returns success even if user doesn't exist (prevents enumeration). `PASSWORD_RESET_REQUESTED` audit entry.
- **Token TTL.** 1 hour. On consumption, `resetPassword` rejects if `usedAt IS NOT NULL` (single-use) or `expiresAt < NOW()`.
- **Single-use enforcement.** On successful reset, row updated `usedAt = NOW()` AND all other rows for that userId DELETED (`users.ts:1862`). Prevents parallel-token confusion, narrows abuse window.
- **iOS deep-link handling.** `AppRoot` / `EusoTripSession` parses `eusotrip://`, extracts `token`, calls `auth.resetPassword({ token, newPassword })`. Token never leaves URL for telemetry; iOS strips from any crash-report URL capture.

---

## 8. Pulse watch auth — WCSession fan-out, shared Keychain, OrbStateMachine

Pulse `AuthStore` holds `token, userId, userName, role`. Persistence mirrors iPhone: Keychain with `kSecAttrAccessibleAfterFirstUnlock`, service `com.eusotrip.watch.auth`, access group `$(AppIdentifierPrefix)com.app.eusotrip.shared`.

**Transports, precedence order:**

1. **Shared keychain access group.** Either target reads other's token with zero WCSession. Lines 41–82 of watch `AuthStore` resolve team prefix at runtime by probing throwaway generic-password item; failures degrade gracefully by omitting `kSecAttrAccessGroup`. L3 resilience path.
2. **WCSession `applicationContext`** — when paired and both running, iPhone pushes `{ token, userId, userName, role }` as most-recent state. Watch calls `AuthStore.update(...)`.
3. **WCSession `transferUserInfo`** — queued delivery for when watch out of range or off; survives reboots.
4. **WCSession `sendMessage`** — immediate, reachable-only; used for sign-out wipes + simulator debug.

Fan-out in `EusoTrip/Services/WatchAuthBridge.swift`, invoked by `EusoTripSession` on sign-in, `/auth.me` success, sign-out.

**OrbStateMachine auth-absent handling.** When `AuthStore.token == nil`, watch orb shows "Open EusoTrip on iPhone to pair" and OrbStateMachine parks in `.awaitingAuth`. No load, HOS, or messaging fetched. `isSignedIn` (`token != nil`) is sole gate. In DEBUG on simulator, `mockSignInForSimulator()` lays down synthetic driver identity.

---

## 9. Certificate pinning — pin the Azure certificate

Backend is Azure App Service. iOS should pin leaf OR intermediate certificate via `NSAppTransportSecurity` + `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)` evaluating server trust against bundled public key. **Current state: not yet implemented.** TLS relied on for MITM.

Doctrine: Wave 2 ships pinning against both Azure-issued leaf public-key SPKI hash AND backup intermediate, with kill-switch config key to disable in emergency rotation. Pin-failure logs to separate endpoint that is NOT pinned (otherwise pinning error becomes unrecoverable).

---

## 10. App Transport Security — TLS 1.3 minimum, no plain HTTP

`Info.plist` declares `NSAppTransportSecurity.NSAllowsArbitraryLoads = false`. No per-domain exceptions. Minimum TLS 1.3; downgrade to 1.2 is a finding. Only permitted plain-HTTP: lifecycle `localhost` in `DEBUG`-only simulator builds, gated `#if DEBUG`. Azure enforces TLS termination with managed certs; origin-to-App-Service always HTTPS.

---

## 11. PII handling — what we store, at-rest and in-transit

**PII inventory (MySQL `users + companies + drivers + documents`):**
- Identity: full name, email, phone, DOB (drivers only).
- Credentials: bcrypt `passwordHash` (cost 12), TOTP secret (AES-256-GCM), backup codes (SHA-256 hashed).
- Driver regulated: **CDL number, CDL state, CDL expiry, medical certificate number, MVR**.
- Business: EIN, DUNS, USDOT, MCN, address, insurance policy numbers.
- Financial: bank account last-4 (full numbers at Stripe/Plaid), Stripe customer id, Plaid access token (encrypted).
- Location: real-time GPS breadcrumbs on `location` router; historical HOS logs on `eld`.

**At rest.** MySQL on Azure Database for MySQL Flexible Server with Azure-managed TDE. Column-level encryption via `sensitiveData.encrypt/decrypt` (re-exported from `_core/trpc.ts`) for SSN, CDL, bank accounts, EIN. Masking helpers (`maskSSN, maskCDL, maskBankAccount, maskEIN`) applied before log writes; `sanitizeLogMessage / sanitizeForStorage` from `pciCompliance.ts` scrubs credit-card patterns unconditionally.

**In transit.** TLS 1.3 everywhere. Internal Azure backplane uses Microsoft's encrypted backbone.

**MDM-unfriendly data: driver CDL.** PII explicitly NOT eligible for MDM sync or export. Corporate MDM platforms often pull shared keychain items as part of device-inventory exports; because Pulse watch token shares access group, any MDM policy applied to iPhone could exfiltrate driver token. **Doctrine**: Pulse watch target must be excluded from MDM profile in customer fleets, OR access group demoted to app-only and WCSession re-established as sole transport.

---

## 12. GDPR, CCPA, US-state privacy — access / delete / retention

- **DSAR (Data Subject Access Request).** `GET /api/privacy/export` + `superAdmin.exportUserData` — returns every row keyed on user across `users, loads, bids, payments, documents, auditLogs, location, hos, messages`. JSON bundle + CSV companion via presigned URL, 7-day download window.
- **Right to delete.** `auth.deleteAccount` (planned) cascades soft-delete to `users.deletedAt`, anonymizes `users.name, email, phone`, triggers `auditLogs` entry `ACCOUNT_DELETED`. Regulatory obligations (DOT drug-test records, HOS logs 6-month retention) override deletion — rows re-keyed to pseudonymous `deleted-user-<id>` tombstone rather than removed.

**Retention policies:**
- HOS logs: 6 months (FMCSA 395.8).
- Driver qualification files: 3 years after termination (FMCSA 391.51).
- Accident records: 3 years (FMCSA 390.15).
- Financial records: 7 years (IRS).
- Audit logs: 7 years (SOC 2 CC7.3).
- Marketing PII with no transactional link: 24 months rolling.

**Jurisdictions.** GDPR (EU), CCPA (CA), CPRA (CA sensitive data), VCDPA (VA), CPA (CO), CTDPA (CT), UCPA (UT), TX TDPSA, OR OCPA, MT MCDPA. Privacy policy declares global-highest-standard to avoid per-jurisdiction branching.

**Consent.** Collected at registration (Terms + Privacy checkbox), logged with IP + UA + timestamp to `auditLogs.action = "CONSENT_RECORDED"`. Re-consent triggered on material policy change.

---

## 13. SOC 2 — audit trail in auditLogs / auditCompliance / blockchainAudit

SOC 2 Type II readiness rests on three router surfaces:

- **`routers/auditLogs.ts`** — append-only log query. Events written by `recordAuditEvent()` in `_core/auditService.ts`.
- **`routers/auditCompliance.ts`** (46K lines) — compliance reporting: control coverage per CC-* control, control-test evidence, gap analysis, report export.
- **`routers/blockchainAudit.ts`** — optional Merkle-anchored audit trail for high-value events (financial, RBAC violations, data exports). Hashes batched daily, anchored to public chain for tamper-evident guarantees.

Every tRPC call traverses `autoAudit` middleware. Records `procedure, type, durationMs, userRole`, on error `errorCode + errorMessage`. Severity HIGH for FORBIDDEN, MEDIUM otherwise. Satisfies **CC6.2** (logical access monitoring), **CC6.3** (access changes logged), **CC7.1** (anomaly detection feed), **CC7.2** (security event review).

**Gaps.** No automated alerting on RBAC_VIOLATION stream. Human-readable dashboard needed; data captured but un-surveilled.

---

## 14. HIPAA — out of scope, flagged

EusoTrip moves freight. Some loads categorized `pharmaceuticals` in product catalog (registration.ts:218) — **packaged pharma**, not identifiable patient specimens. **HIPAA does not apply.**

If/when platform moves clinical specimens (blood, tissue, patient ID-linked) or patient medical records:
- BAA with every lab / hospital shipper.
- Encryption at rest upgraded to FIPS 140-2.
- New role `MEDICAL_COURIER` with restricted PHI access.
- Audit retention extended to 6 years (HIPAA §164.316).
- Breach-notification pipeline within 60 days.

Flag: medical-courier expansion is Wave 3 per product roadmap. Engineering consulted before first patient-linked shipment.

---

## 15. Hazmat data security — placarding, need-to-know, route secrecy

Hazmat loads carry compliance burden beyond PII. Product catalog entries with `requiresHazmat: true` (crude_oil, refined_fuel, jet_fuel, LPG, anhydrous ammonia, LNG, LOX, liquid nitrogen, industrial chemicals, hazmat_dry) trigger additional access rules:

- **Who sees what.** Full hazmat manifest (UN number, packing group, placard class, emergency contact) visible to `DRIVER, DISPATCH, CATALYST` (carrier side), `SHIPPER, COMPLIANCE_OFFICER, SAFETY_MANAGER, ESCORT`. **Public-tier brokers and unauthenticated shippers see only redacted summary.**
- **Placarding rules.** `hazmat.ts` router enforces that driver's CDL hazmat endorsement (`users.metadata.registration.hazmatEndorsed = true`, company-side `companies.hazmatLicense`) is valid before hazmat load accepted. No endorsement → 403 at `loadLifecycle.accept`.
- **Route secrecy.** Hazmat routes NOT rendered in public load boards, search indexes, or embeddings. `embeddings.ts` skips any load with `hazmatClass IS NOT NULL` unless caller's isolation scope includes that company. Public title masked to `"Hazmat Class X Transport"` without origin/destination.
- **Security plan.** `shipperRegistration.hasSecurityPlan` flag required per 49 CFR 172.800 for Class 1, 2.3, 4.3, 5.1, 6.1, 7 loads. Enforced at registration.
- **PHMSA / HM-232.** Drivers on Class 1.1–1.3, 2.3, 5.1 must have TWIC. `companies.twicCard / twicExpiry` columns track.

---

## 16. Payment security — PCI-DSS scope reduction

EusoTrip does not store Primary Account Numbers (PAN). Ever. Full scope-reduction via:

- **Stripe** — card-on-file held by Stripe (PCI Level 1). Server holds only `stripe_customer_id` + `stripe_payment_method_id` tokens. Stripe.js (web) and Stripe iOS SDK tokenize cards client-side; origin never touches PAN. Webhooks (`routers/stripe.ts`) signature-validated against `STRIPE_WEBHOOK_SECRET`.
- **Plaid** — ACH / bank linkage. Store `plaid_access_token` (encrypted), `plaid_item_id`, bank last-4 + routing — never full account.
- **PAN never in logs.** `pciCompliance.sanitizeLogMessage` scrubs any 13–19 digit contiguous number passing Luhn. Applied in tRPC logger pipeline.
- **SAQ level.** Qualify for SAQ-A (card-not-present, fully outsourced to token vaults) — narrowest PCI-DSS scope, ~22 controls instead of 329.

---

## 17. Secrets management — xcconfig + Azure App Settings, zero-git

- **iOS secrets.** HERE Maps, Gemini (client-facing limited scope), Azure Communication Services keys in `EusoTrip.xcconfig / EusoTrip.private.xcconfig`. `.private.xcconfig` gitignored; CI injects from 1Password. Info.plist reads as `$(HERE_ACCESS_KEY_ID)` etc.
- **Server secrets.** Azure App Service App Settings (encrypted at rest in Azure Key Vault references). Keys: `JWT_SECRET, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, PLAID_SECRET, GEMINI_API_KEY, HERE_ACCESS_KEY_ID, HERE_ACCESS_KEY_SECRET, ACS_CONNECTION_STRING, DATABASE_URL, MFA_ENCRYPTION_KEY`.
- **Git hygiene.** `.env*, *.xcconfig, *.p8, *.p12, GoogleService-Info.plist`, and anything matching `secret|token|credentials|apiKey` in filename blocked by pre-commit hook + GitHub secret-scanning. Historical leak rotated within 24h; one documented HERE key rotation from October 2025.

**Rotation cadences:**
- `HERE_ACCESS_KEY_SECRET` — **90 days**.
- `JWT_SECRET` — 180 days (coordinated with session-TTL shortening, §2).
- `STRIPE_WEBHOOK_SECRET` — annually or within 24h of suspected disclosure.
- `MFA_ENCRYPTION_KEY` — annually; envelope-encrypted secrets re-wrapped on rotation.
- `PLAID_SECRET` — per Plaid schedule (annual).
- Database credentials — quarterly, zero-downtime rotation via Azure Key Vault dynamic references.

---

## 18. Known vulnerabilities (SKILL.md §16)

Inherited for transparency and tracking:

1. **`auth.revokeAllSessions` is a no-op.** Returns success without invalidating outstanding JWTs. Super-admin compromise not containable via this primitive. **Severity: P0.** Remediation: introduce `session_id` claim inside JWT, persist revocation list keyed by userId + issuedBefore timestamp, gate `requireUser` on revocation check. Ship Wave 2.

2. **`registerAdmin` is a `publicProcedure` (`auditedPublicProcedure`).** Anyone knowing invitation codes `EUSOTRIP-ADMIN-2026` or `EUSORONE-INVITE` (hardcoded `registration.ts:1547`) can self-register ADMIN or SUPER_ADMIN. Invitation codes leaked into this doctrine file and every git blame. **Severity: P0.** Remediation: rotate codes to per-invite UUIDs in `admin_invitations` table with single-use + expiry, route through `superAdminProcedure`, require email allow-list. Ship immediately.

3. **Super-admin email hardcoded.** Embedded in backend bootstrap (a.lynngambardella-class address, per git history). First-run seeding grants `SUPER_ADMIN` to that email. If attacker controls inbox, they control platform. **Severity: P1.** Remediation: move to App Settings (`SUPER_ADMIN_EMAIL`), require MFA-on-first-login, rotate email before Wave 1 GA.

**Other latent issues:**
- Legacy SMS 2FA stores codes in plaintext on `users.metadata` (§3).
- `users.openId` serves dual-duty as email verification token (§6).
- No automated RBAC_VIOLATION alerting (§13).
- No certificate pinning yet (§9).
- 365-day session TTL (§2).

---

## 19. Vulnerability disclosure program + bug bounty

Must publish coordinated vulnerability disclosure (CVD) before GA. Recommended:

- **`security.txt`** at `https://eusotrip.com/.well-known/security.txt` per RFC 9116, listing `Contact: mailto:security@eusotrip.com`, `Expires:`, `Preferred-Languages: en`, `Canonical:`, `Policy: https://eusotrip.com/security/policy`.
- **PGP key** published for encrypted disclosure.
- **Safe-harbor clause.** Good-faith researchers complying with program scope, not accessing data beyond POC, not disrupting service will not face legal action under CFAA or state equivalents.
- **Scope.** `*.eusotrip.com`, `*.eusorone.com`, iOS EusoTrip, iOS Pulse Watch app. Out of scope: marketing sites, third-party vendors (Stripe, Plaid, HERE, Azure).
- **Response SLAs.** Acknowledge 3 business days; initial triage 10; fix/mitigation plan 30; public disclosure coordinated after fix.
- **Bug bounty (recommended, not yet funded).** Launch via HackerOne / Bugcrowd after 6 months of CVD. Payout matrix: Critical $5K–$10K (RCE, auth bypass, cross-tenant data), High $2K–$5K (privilege escalation, PII leak), Medium $500–$2K, Low $100–$500. Budget $100K/year initially.
- **Hall of Fame** page to acknowledge researchers, opt-in attribution.

Engineering treats any P0/P1 from program as production incident (follow incident-response runbook, [92_Launch_Runbook_and_Rollback.md](./92_Launch_Runbook_and_Rollback.md)), with public post-mortem where legally permissible.

---

## Closing posture

EusoTrip's auth and security posture is workable for Wave 1 but carries three P0 items (`revokeAllSessions` no-op, `registerAdmin` public, hardcoded super-admin email) that must be remediated before GA.

Strongest primitives:
- Audited procedure middleware (every call logged).
- TOTP-based MFA service (encrypted at rest).
- Isolation middleware (when used consistently).
- PCI scope-reduction via Stripe/Plaid tokens.

Weakest:
- Session lifecycle (365-day TTL, no effective revocation).
- Three parallel MFA surfaces.
- Absence of certificate pinning.

Roadmap closes these in Wave 2. Auditors should be walked through this document first, remediation Jira epic second.

**Owners**: Platform Security (primary), Backend Infra (session + isolation), iOS Platform (keychain + pinning), Compliance (SOC 2, GDPR, HIPAA-readiness), Legal (CVD safe-harbor, privacy policy, state-privacy expansion).

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
