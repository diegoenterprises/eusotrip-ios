# 91 · Mobile ↔ Web Platform Parity + Continuity

**What this covers.** The non-negotiable shared-everything principle between iOS and web — one backend, one database, one auth, one DTO, one design token file, one icon map, one locale file, one set of user journeys, two renderers. Breaking change policy (14-day dual-response window, 30 days when touching App-Store-reviewed iOS builds). Naming convention discipline (`Mobile` suffix rules). Design system cross-reference (CSS variables ↔ Swift). Iconography (SF Symbols ↔ Lucide). Translations. Testing parity. Cross-platform journeys that MUST work. Real-time sync. Auth cookie sharing. Role switching. Deep-linking. Apple Handoff. Release cadence. Coordination rituals. Gap lists (iOS-only and web-only). API versioning via feature flags (never URL versioning). Source: wave-1 shard `team_WEB_PARITY`.

**When you need this.** Before changing a shared DTO. Before creating a `Mobile`-suffixed route. When wiring a new feature — the question "does this need to exist on web?" is asked every time. When debugging "works on web, broken on iOS" (root cause is almost always drift).

**Cross-links.** Backend: [03_Backend_API_Contract.md](./03_Backend_API_Contract.md). Brand tokens: [01_Brand_DNA_and_Design_Rules.md](./01_Brand_DNA_and_Design_Rules.md). Journeys: [80_User_Journeys_and_Load_Lifecycle.md](./80_User_Journeys_and_Load_Lifecycle.md).

---

## 0. The non-negotiable premise

A driver opens EusoTrip iOS at a truck stop in Amarillo and checks wallet. Balance: $2,347.18. Twelve transactions this week. HOS clock shows 4h 22m remaining on 11-hour driving window. Thirty minutes later, sitting in motel room, same driver opens browser on borrowed laptop, logs into eusotrip.com, navigates to same wallet. Balance: $2,347.18. Twelve transactions. HOS clock: 3h 52m (because time has passed — but the clock is the same clock, not a new one).

**This is not aspirational. This is the floor.** If iOS and web ever disagree about what user's data is, product is broken. Period. No amount of design polish, no amount of native animations, no amount of feature richness rescues a platform where truth depends on which device you picked up. **EusoTrip is one product with two renderers. The renderers are allowed to differ. The truth is not.**

---

## 1. Shared-everything principle

**One backend**. Address `eusotrip-app.azurewebsites.net`. iOS hits it. Web hits it. **No "mobile API" and no "web API." There is the API.** iOS app and web app are both clients of same tRPC router tree, same stored procedures, same MySQL database hosted in Azure, same Drizzle schema, same JWT cookie authentication.

Not a convenience decision. Architectural commitment with specific consequences:

**One source of truth.** When driver accepts load on iOS, single `loads.accept` procedure executes against single `loads` table. No "mobile loads table" syncing with "web loads table." No event bus fanning out between platform-specific stores. The database is the only place state lives.

**One authentication surface.** JWT cookie issued by backend valid for both clients. iOS stores in Keychain + attaches to every request. Web stores as HttpOnly cookie + browser attaches automatically. Backend does not care which client presented the token — cares only whether token valid and what user ID it resolves to.

**One permissions model.** Backend owns authorization. Driver who cannot see load detail `L-48291` on web also cannot see it on iOS — same `canAccessLoad(userId, loadId)` predicate runs in same procedure regardless of caller. Role checks, tenant boundaries, row-level security live in backend. **Clients never enforce.** Clients only render what backend returns.

**One audit log.** Every mutation writes to `audit_events` with `client` field (`ios | web | admin`) so we know where action originated, but event itself is one event. No bifurcated history.

If you find yourself reaching for platform-specific backend route, **stop**. Default is shared. Burden of proof for divergence is high.

---

## 2. Naming convention discipline

tRPC routers grouped by domain. One canonical namespace per domain:
- `wallet.*` — earnings, balances, transactions, payouts.
- `loads.*` — load lifecycle, offers, acceptance, status updates.
- `hos.*` — hours of service, duty status, driving clocks.
- `chat.*` — messages, threads, presence.
- `documents.*` — BOL, POD, rate confirmations.
- `profile.*` — user profile, preferences.
- `fleet.*` — vehicle + trailer management.

**No `walletMobile.*`. No `loadsiOS.*`. No `hosMobileV2.*`. Forbidden.** Produce drift, produce two sources of truth, produce bug reports that say "works on web, broken on iOS" and root cause is always two namespaces forked six months ago and nobody noticed.

**The exception, and the only exception.** Sometimes shape of data legitimately differs for mobile. Mobile client is bandwidth-constrained, battery-constrained, renders smaller screen that doesn't need every column. In that case, mobile variant lives in same router, with `Mobile` suffix, calls same underlying service layer:

```typescript
export const walletRouter = router({
  list: protectedProcedure.query(async ({ ctx }) => {
    return walletService.list(ctx.userId); // full shape
  }),
  listMobile: protectedProcedure.query(async ({ ctx }) => {
    const full = await walletService.list(ctx.userId);
    return full.map(t => ({
      id: t.id,
      amount: t.amount,
      date: t.date,
      summary: t.summary, // mobile cares only about these four
    }));
  }),
});
```

**Rules for `Mobile` suffix:**
1. Lives in same router file as desktop sibling. No separate file, no separate directory.
2. Calls same service-layer function. Divergence is projection only, never logic.
3. Documented with one-line comment explaining why mobile shape differs.
4. Reviewed by web lead AND iOS lead — web lead must understand mobile shape exists.

**Any `Mobile` suffix adding business logic not present in desktop sibling is a bug. File immediately.**

---

## 3. Data model parity

iOS decodes JSON into Swift `Codable` structs. Web decodes JSON into TypeScript interfaces inferred from tRPC. **JSON is the same JSON.** Means:

- Add a field → both clients must decode. Swift `Codable` with optional fields handles gracefully; TypeScript does too.
- Remove a field → breaks both clients simultaneously. **Don't remove. Deprecate (§4).**
- Rename a field → breaks both. **Don't rename. Add new, dual-write for deprecation window, then remove.**
- Change a field's type (e.g., `amount` from cents-as-integer to dollars-as-string) → breaks both. **Don't.**

DTO is a contract. Narrowest part of the system, most brittle. Treat with reverence of a public API — to two client teams, it IS the public API.

---

## 4. Breaking change policy

When response shape must change, procedure returns both old and new shapes simultaneously for fourteen days, then old removed.

```typescript
// Day 0: dual-response begins
export const walletList = protectedProcedure.query(async ({ ctx }) => {
  const transactions = await walletService.list(ctx.userId);
  return {
    // old shape, deprecated
    items: transactions.map(oldProjection),
    // new shape
    transactions: transactions.map(newProjection),
    _deprecated: ['items'],
  };
});
// Day 14: old shape removed
```

During 14-day window, iOS + web teams each cut over at own pace. `_deprecated` array surfaced to client logs — track uptake. On day 14, backend removes `items`; any client still reading gets decode error — intentional, client team's responsibility to have shipped migration.

**14 days is floor, not ceiling.** For changes affecting App-Store-reviewed iOS builds, extend to **30 days** because Apple review adds latency.

---

## 5. Feature flag parity

Feature flags defined in one place, consumed by both clients. When web feature ships behind `enable_wallet_v2`, same flag controls iOS wallet redesign. Two platforms should light up within two weeks of each other.

Exception is genuinely platform-specific — Apple Watch complications, iOS Live Activities, web-only admin consoles. Get flags with platform prefixes: `ios_live_activity_hos, web_admin_bulk_import`. Prefix declares feature scoped to one platform, won't be matched on other.

If feature is not platform-prefixed and ships only on web, mirror ticket for iOS auto-created. Same reverse. **Parity is default; divergence requires deliberate tag.**

---

## 6. Design system cross-reference

Design tokens are second-narrowest contract after DTO. Two representations describing one system.

**iOS side**. `DesignSystem.swift` exports `Brand` struct with color properties: `Brand.blue, Brand.magenta, Brand.ink, Brand.neutral100 through Brand.neutral900`. Exports `LinearGradient` namespace with `.diagonal, .vertical, .horizontal`. Exports typography, spacing, radius tokens.

**Web side**. CSS variables on `:root`: `--brand-blue, --brand-magenta, --brand-ink`. Tailwind configured to consume via `theme.extend.colors`. shadcn primitives use same variables. Gradients expressed as `linear-gradient(135deg, var(--brand-blue), var(--brand-magenta))`.

**Mapping is 1:1 and enforced by shared JSON file — `design-tokens.json`** — the source of truth. Both `DesignSystem.swift` + web CSS variables are generated (or checked in CI) from this file. PR changing hex value in one platform without updating JSON fails CI.

Specific mappings:

| Token | iOS (SwiftUI) | Web (CSS) | Hex |
|---|---|---|---|
| Primary | `Brand.blue` | `var(--brand-blue)` | `#2B5CFF` |
| Accent | `Brand.magenta` | `var(--brand-magenta)` | `#E6008B` |
| Ink | `Brand.ink` | `var(--brand-ink)` | `#0B0F1A` |
| Success | `Brand.emerald` | `var(--brand-emerald)` | `#10B981` |
| Danger | `Brand.red` | `var(--brand-red)` | `#EF4444` |
| Diagonal gradient | `LinearGradient.diagonal` | `linear-gradient(135deg, var(--brand-blue), var(--brand-magenta))` | — |

Typography and spacing follow same generation rule. Designer wanting to shift `--brand-blue` by two hex units updates `design-tokens.json`; both platforms pick up change on next build.

---

## 7. Iconography

iOS uses SF Symbols. Web cannot (Apple proprietary). Web uses canonical open-source set — **Lucide** — because actively maintained, broad coverage, ships as React components that tree-shake.

Mapping between SF Symbol names + Lucide names maintained in `icon-map.json`:

```json
{
  "wallet": { "sf": "creditcard.fill", "lucide": "Wallet" },
  "hos-clock": { "sf": "clock.badge.checkmark", "lucide": "Clock" },
  "load": { "sf": "shippingbox.fill", "lucide": "Package" },
  "chat": { "sf": "bubble.left.and.bubble.right.fill", "lucide": "MessageSquare" },
  "route": { "sf": "map.fill", "lucide": "Map" },
  "fuel": { "sf": "fuelpump.fill", "lucide": "Fuel" }
}
```

When designer introduces new icon, adds row to this map. Both platforms pick up. **No scenario where iOS uses wallet icon + web uses totally different metaphor** — metaphor is registered, two platforms render registered metaphor in their respective libraries.

---

## 8. Translations

i18n files shared. One directory `locales/`, one file per locale: `en.json, es.json, fr.json, pt.json`. iOS reads at build time and converts to `Localizable.strings`. Web reads at build time and bundles into JS payload.

Translation keys namespaced by feature: `wallet.balance.title, hos.clock.remaining, loads.offer.accept_button`. **Key that exists in one platform exists in all platforms.** CI enforces: if `en.json` has key `es.json` lacks, build fails until either key translated or explicitly marked `{ "__pending_translation": true }`.

User-facing strings do not live in component code on either platform. Live in locale files + referenced by key. How we keep Spanish drivers getting same messaging as English, on same platform Spanish web dispatcher is reading.

---

## 9. Testing parity

Every shared backend procedure has two end-to-end tests: one iOS XCUITest through native UI, one web Playwright (or Cypress) through browser UI. Both live alongside procedure definition, or in paired repos with CI running on every backend change.

Tests not identical in shape — iOS uses accessibility identifiers, web uses CSS selectors and role queries — but exercise same user journey and assert against same backend state. If change to `loads.accept` passes iOS test and fails web test, **we have parity bug and ship neither until both pass**.

**Test matrix:**
- Backend procedure tests (unit-ish, mock DB): every backend PR.
- Backend integration tests (real DB, no client): every backend PR.
- iOS XCUITest suite: nightly + every iOS PR.
- Web Playwright suite: every web PR + nightly against staging.
- Cross-platform suite: small set specifically exercising journeys in §10. Nightly.

---

## 10. Cross-platform user journeys

Following journeys MUST work end-to-end. Tested.

**Create load on web, accept on iOS.** Dispatcher creates load in web console. Thirty seconds later, driver's iOS receives push for offer. Driver taps accept. Dispatcher's web updates in real time showing load accepted + assigned.

**Start HOS clock on iOS, see HOS on web dispatcher screen.** Driver goes on-duty in iOS HOS module. Web dispatcher viewing driver's card sees duty status change from Off-Duty to On-Duty within two seconds. Clock begins ticking on both screens, displayed remaining time is same number.

**Sign BOL on iOS, PDF available on web immediately.** Driver captures BOL signature on iOS. Document uploaded, PDF generated server-side, within five seconds available in web document center for office to print or forward to broker.

**Chat on web, iOS push notification.** Office user sends message to driver through web chat. Driver's iOS device receives APNs push within one second. Tapping notification opens driver's iOS chat thread, scrolled to new message.

**Role switch on web, role switch on iOS.** User with both driver + dispatcher roles switches to dispatcher on web. When they open iOS later, they land in role last used on any platform. **Last-role-used is server-side preference, not client-local.**

These journeys are parity contract expressed as behavior. Not aspirational. Tested nightly. Regressions block releases.

---

## 11. Real-time sync

Mechanism for real-time sync — WebSocket subscriptions via tRPC, or short-interval polling — must behave identically on both platforms. If web uses WebSocket for HOS clock updates, iOS uses WebSocket for HOS clock updates. If iOS falls back to polling when WebSocket fails, web falls back to polling too. Fallback thresholds + intervals documented in one place, implemented identically.

Do not let iOS + web diverge on sync strategy. User seeing five-second stale clock on one device and one-second fresh clock on other will (correctly) file bug; root cause will be two clients with different sync configurations.

---

## 12. Authentication cookie sharing

If both iOS + web served from same root domain — `eusotrip.com` — JWT cookie set with `Domain=.eusotrip.com; Secure; HttpOnly; SameSite=Lax` works across subdomains and, with care, across native-to-web bridges.

On iOS, when we need to hand logged-in user into web view (for admin surfaces or documentation), use `SFAuthenticationSession` / `ASWebAuthenticationSession` which shares Safari cookie jar. User does not re-authenticate. How single-sign-on "just works" between iOS app and web-hosted admin console.

If iOS logs out, also clear `SFSafariViewController` cookie (via `WKWebsiteDataStore` for embedded web views, or accept Safari's cookie jar persists + document). **Consistency preferred.**

---

## 13. Role switching

User with multiple roles — driver + dispatcher, or owner-operator + fleet manager — sees same role selector on iOS + web. Selector lives in top-right of primary navigation, shows current role, lists alternates on tap.

Selected role stored on user record, not on device. Switching on web updates server; iOS picks up on next app open or via push if backgrounded. User experience: "I switched to dispatcher mode on my Mac, and now my phone also shows dispatcher mode." **One user, one current-role, visible everywhere.**

---

## 14. Deep-linking

iOS deep links use `eusotrip://` custom scheme + universal links on `eusotrip.com/r/`. Web deep links use `eusotrip.com/r/` directly. Both resolve to same destination.

`eusotrip://loads/L-48291` on iOS and `https://eusotrip.com/r/loads/L-48291` on web both open load detail for L-48291. Dispatcher can paste link into Slack; any recipient — phone, laptop, iPad — can click and land on same content.

Link resolver is shared spec. Resolver on iOS and resolver on web consume same route map, defined in shared JSON. Adding new deep-linkable surface means adding entry to map — both platforms pick up.

---

## 15. Handoff

Apple Handoff lets user viewing content on Mac (in Safari or native Mac app) pick up same content on iPhone, or vice versa. EusoTrip participates via `NSUserActivity` on iOS + `<meta name="apple-itunes-app">` / universal-link associations on web side.

Dispatcher viewing load L-48291 on Mac sees EusoTrip app icon appear on iPhone lock screen. Tap it → land on same load detail in iOS. Configured per screen, not globally — screens representing single identifiable entity (load, driver, document) are Handoff-eligible; transient screens are not.

---

## 16. Release cadence

iOS + web ship in lockstep for major features. If "Wallet v2" launching, both clients ship UI same day, or within narrowest window App Store review allows (typically iOS releases 24–72 hours after web due to review lag).

For bug fixes, cadence independent. Web hotfix can ship in hours; iOS hotfix takes minimum a day for review. **We do not hold web releases for iOS parity on bug fixes** — ship web immediately + follow with iOS.

Release train:
- Web: continuous deployment, multiple deploys per day.
- iOS: weekly TestFlight, biweekly App Store, hotfix exceptions.
- Backend: continuous deployment, gated by schema migration review.

---

## 17. Coordination rituals

**Weekly sync meeting.** iOS lead, web lead, backend lead. Thirty minutes. Agenda: breaking changes incoming, parity gaps discovered, release coordination. Minimum viable coordination surface.

**Shared JIRA/Linear board.** Every ticket touching product tagged with affected platforms: `#ios, #web, #backend`. Ticket tagged `#ios #web #backend` is cross-cutting and won't mark done until all three surfaces ship.

**PR cross-review.** Backend PR changing shared DTO requires review from both iOS lead AND web lead. GitHub CODEOWNERS enforces for relevant files.

**Shared Slack channel: `#eusotrip-parity`.** Questions like "is this field available on web yet" and "is iOS build picking up new flag" happen here. **Not in DMs.** Channel is searchable history for when future engineers try to understand why divergence exists.

---

## 18. Current iOS-only surfaces (gap list)

Features present on iOS and absent (or materially weaker) on web:

- Pulse Apple Watch companion.
- Native biometric authentication (Face ID / Touch ID).
- Offline-first wallet + HOS cache.
- HERE Maps tile overlay with offline regions.
- Voice dispatch (on-device speech recognition).
- Haptic feedback for critical confirmations.
- CoreMotion-based fatigue detection.
- CoreLocation geofence triggers for geofenced tasks.

Some inherently native + cannot be mirrored on web (CoreMotion, CoreLocation geofences, haptics). Others could be mirrored with effort (offline-first via service workers, biometric auth via WebAuthn). **Gap list reviewed quarterly.**

---

## 19. Current web-only surfaces (gap list)

Present on web and absent on iOS:

- Admin console (tenant settings, billing, user management).
- Tenant manager (multi-tenant switcher for super-admins).
- Advanced analytics (dashboards, cohort reports, export).
- Control tower (multi-load situational awareness for dispatch).
- Bulk import (CSV load upload, driver roster upload).
- Super-admin surfaces (internal support tooling).

Most dispatcher- + admin-oriented; small-screen form factor is genuinely poor fit. **We accept gap.** Do not intend to port admin console to iOS. **Do** intend to port control tower to iPad at some point.

---

## 20. Shared components to extract

Canonical DTO definitions are primary shared artifact. On web, tRPC infers TypeScript types directly from backend procedure signatures — client has no manual type definitions, generated. On iOS, we manually map Codable structs to same shapes + verify with CI step reading tRPC schema + confirming every Swift struct field matches.

Over time we intend to investigate automated Swift code generation from tRPC schemas, but current manual approach with CI verification is sufficient.

---

## 21. Schema evolution

Drizzle is ORM. Migrations code-defined + run in CI before every backend deploy. When schema change lands:
1. Drizzle migration file written + reviewed.
2. CI runs migration against staging DB, verifies success.
3. Backend deploy applies migration in production.
4. If schema change affects shared DTO, DTO change follows §4 breaking-change policy.
5. iOS Codable structs + web TypeScript types pick up new shape on next build.

Destructive migrations (column drop, table drop) go through **three-phase process**: deploy code no longer reading column, wait two weeks, deploy migration dropping column. Prevents scenario where old client reads column that no longer exists.

---

## 22. Error taxonomy

Backend returns errors with stable codes: `AUTH_EXPIRED, LOAD_NOT_FOUND, HOS_VIOLATION_DETECTED, WALLET_INSUFFICIENT_FUNDS`. Codes identical across platforms. Each maps to user-facing message in each locale:

```json
{
  "errors": {
    "AUTH_EXPIRED": "Your session expired. Please sign in again.",
    "LOAD_NOT_FOUND": "This load is no longer available.",
    "HOS_VIOLATION_DETECTED": "Continuing would violate HOS rules."
  }
}
```

iOS + web both look up messages from shared locale file. **Error code is the contract. Copy is localizable.** Driver seeing "Your session expired" in English on phone sees identical phrasing in web client.

---

## 23. Onboarding parity

User completing registration on web can immediately log in on iOS with same credentials. **No second onboarding.** No re-entry of profile data. Registration record lives in users table, platform-agnostic.

User onboarding on iOS (downloads app, signs up) can immediately log in on web. Registration is one-time event scoped to account, not to platform.

---

## 24. Downtime gracefully

When backend unavailable:

**iOS** enters offline mode. Wallet shows last-cached balance with timestamp. HOS clock continues running locally from last-known duty status. Writes queued to local `outbox` + flushed when connectivity returns. UI surfaces unobtrusive banner: "Working offline — changes will sync when you reconnect."

**Web** shows full-width banner: "Service temporarily unavailable. We're working on it." Writes not queued (browser is poor offline store for business-critical data, desktop users have less expectation of offline). Reads serve cached data where available via HTTP cache, but user told not to rely on them.

Asymmetry is intentional. iOS is field tool used in low-connectivity environments; web typically used in offices with broadband. **Offline contracts reflect user context.**

---

## 25. API versioning strategy

tRPC does not version procedures. **We do not have `wallet.v1.list` and `wallet.v2.list`.** Versioning by URL is anti-parity — invites two clients to use two versions in perpetuity.

Instead, evolve procedures in place using feature flags. New behavior gated behind `enable_wallet_v2`; procedure branches internally:

```typescript
export const walletList = protectedProcedure.query(async ({ ctx }) => {
  if (await flags.enabled('enable_wallet_v2', ctx.userId)) {
    return walletServiceV2.list(ctx.userId);
  }
  return walletServiceV1.list(ctx.userId);
});
```

When flag fully rolled out, old branch deleted. **One `wallet.list` procedure at all times, evolves.** Clients do not need to know about versions. Call `wallet.list`, receive whatever currently-active shape is, which is same shape for iOS + web simultaneously because flag evaluated server-side per user.

---

## Closing

Parity is a muscle. Atrophies the moment we stop exercising. Every shortcut taken today — quick mobile-only endpoint, color drifting by two hex units, feature shipping on web "and we'll do iOS later" — accumulates interest.

Discipline is simple to state and hard to maintain: **one backend, one database, one auth, one DTO, one design token file, one icon map, one locale file, one set of user journeys, two renderers.**

When driver logs in on phone + sees $2,347.18, and opens laptop + sees $2,347.18, that number is not a coincidence. It is the result of a thousand small decisions made in direction of truth.

**Ship them both. Ship them together. Never let them drift.**

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
