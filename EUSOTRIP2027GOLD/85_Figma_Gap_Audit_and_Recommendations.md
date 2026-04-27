# 85 · Figma Design Gap Audit + Alternate Recommendations

**What this covers.** The Figma-to-backend contract for Wave 1 — every screen 023 through 099 cross-referenced against the tRPC router inventory; gaps flagged; three ordered alternates per gap (Option A reuse, Option B compose, Option C defer); four filtering invariants; priority tier (P0/P1/P2); screens to delete (8 redundant); screens to add (10 Figma missed); high-friction redesign prescriptions; handoff protocol. Source: wave-1 shard `team_FIGMA_gap_audit`.

**When you need this.** When picking up a Figma frame for wiring. When a screen's backend isn't obvious. When scoping a sprint. When deciding to defer vs hack around a backend gap.

**Cross-links.** Backend catalog: [03_Backend_API_Contract.md](./03_Backend_API_Contract.md). Brand + primitives: [01_Brand_DNA_and_Design_Rules.md](./01_Brand_DNA_and_Design_Rules.md). Web parity (drift detection): [91_Web_Mobile_Parity.md](./91_Web_Mobile_Parity.md).

---

## 0. Purpose

SKILL.md §5 defines a 77-item screen queue numbered 023 through 099. Each screen must either (a) map to a canonical tRPC procedure in `frontend/server/routers/`, (b) compose from defined set of existing procedures, or (c) be explicitly deferred behind `EusoEmptyState(comingSoon)` with `TODO(backend-ship)` marker.

This document cross-references every screen in that queue against the router inventory surfaced via MCP `list_directory frontend/server/routers`, flags gaps, prescribes alternate designs preserving four invariants of the EusoTrip ecosystem: **driver mental model, backend data provenance, offline-first fallback, accessibility (WCAG 2.1 AA, glove-mode compatible)**.

Structured so a designer can open it, find a screen ID, and within sixty seconds know (1) whether a backend exists, (2) which procedure to call, (3) what to do if it does not exist, (4) priority tier for launch.

---

## 1. Methodology

1. Enumerated screens 023–099 from SKILL.md §5.
2. Cross-referenced each against `frontend/server/routers/` directory (canonical tRPC routers: `drivers.ts`, `gamification.ts`, `crossBorder.ts`, `esangAI.ts`, `emergencyResponse.ts`, `emergencyProtocols.ts`, `zeunMechanics.ts`, `weather.ts`, `equipCustomization.ts`, `autonomous.ts`, peers).
3. For each "NO BACKEND PROCEDURE EXISTS," produced three ordered alternates: **Option A** (reuse similar canonical procedure), **Option B** (compose from 2–3 existing), **Option C** (defer with empty state).
4. Filtered alternates against four invariants in §0.
5. Assigned priority tier (P0/P1/P2).
6. Flagged screens for deletion (redundant) and addition (gaps Figma missed).

---

## 2. Screen-by-screen cross-reference (023–099)

Legend:
- `CANONICAL` — dedicated procedure exists + wired.
- `PARTIAL` — procedure exists but shape mismatch; adapter required.
- `COMPOSE` — no dedicated procedure; compose from 2–3 existing.
- `GAP` — no backing procedure at all; alternate required.

### 023–029 Onboarding & Auth
- **023 Welcome / Hero** — GAP (static content). Option C: marketing copy only, no RemoteState.
- **024 Sign-In (Email)** — CANONICAL → `auth.signIn`.
- **025 Sign-In (Phone OTP)** — CANONICAL → `auth.requestOTP` + `auth.verifyOTP`.
- **026 MFA Challenge** — CANONICAL → `auth.mfa.challenge`.
- **027 Role Picker** — CANONICAL → `users.getMe` returns `roles[]`; client-side routing.
- **028 Permissions Primer (Location, Motion, Camera, Mic)** — GAP (native-only). No backend; Option C with `TODO(telemetry-ship)` to log grants to `telemetry.logPermissionGrant`.
- **029 Device Pairing (ELD)** — CANONICAL → `drivers.pairELD`.

### 030–039 Home & Dashboard
- **030 Driver Home (Today)** — CANONICAL → `drivers.getToday`.
- **031 Dispatcher Home** — CANONICAL → `dispatch.getBoard` (via `dispatch_board` MCP).
- **032 Broker Home** — CANONICAL → `brokers.getOverview`.
- **033 Shipper Home** — CANONICAL → `shippers.getOverview`.
- **034 Fleet Owner Home** — PARTIAL → `carriers.getScorecard` returns shape but missing `utilization` field. Adapter: compute client-side from `vehicles.list`.
- **035 Global Search** — CANONICAL → `search.universal`.
- **036 Notifications Inbox** — CANONICAL → `notifications.list`.
- **037 Notification Detail** — CANONICAL → `notifications.get`.
- **038 Quick Actions (role-scoped)** — GAP (UI-only). Option C: static config.
- **039 Dark-Mode / Theme Toggle** — GAP (local pref). No backend needed.

### 040–049 Load Lifecycle
- **040 Load List** — CANONICAL → `loads.search` (via `search_loads`).
- **041 Load Detail** — CANONICAL → `loads.get` (via `get_load_details`).
- **042 Load Map** — CANONICAL → `loads.getRoute` + `tracking.getPositions`.
- **043 Exception · Breakdown** — **GAP (high friction).** Requires `zeunMechanics.reportBreakdown`, NOT a custom endpoint. Alternate detailed in §3.
- **044 Exception · Weather** — CANONICAL → `weather.getRouteAlerts`.
- **045 Exception · Traffic** — CANONICAL → `traffic.getIncidents`.
- **046 Exception · Detention** — CANONICAL → `detention.open` + `detention.getTimer`.
- **047 Exception · Accessorial Request** — CANONICAL → `accessorial.request` (backed by `accessorial_stats`).
- **048 Dispatch · Accept Load** — CANONICAL → `drivers.acceptLoad`.
- **049 Dispatch · Reject / Counter** — CANONICAL → `drivers.rejectLoad` + `drivers.counterOffer`.

### 050–059 Documents & Compliance
- **050 POD Capture (portrait)** — CANONICAL → `documents.uploadPOD`.
- **051 POD Signature** — PARTIAL → `documents.attachSignature` exists but UX needs landscape capture flow Figma didn't produce. See §7 ADD.
- **052 BOL Viewer** — CANONICAL → `documents.getBOL`.
- **053 DVIR (Pre-trip)** — CANONICAL → `inspections.start` + `inspections.submit` (via `inspection_records`).
- **054 DVIR (Post-trip)** — CANONICAL → same router, different `phase` param.
- **055 HOS Status** — CANONICAL → `hos.getStatus` (via `hos_status`).
- **056 HOS Logs** — CANONICAL → `hos.getLogs` (via `hos_audit_logs`).
- **057 IFTA Summary** — CANONICAL → `ifta.estimate` (via `ifta_estimate`).
- **058 FMCSA Safety Snapshot** — CANONICAL → `fmcsa.getCarrierSafety`.
- **059 Certifications Wallet** — CANONICAL → `certifications.list` (via `certifications_status`).

### 060–069 The Haul (Gamification)
- **060 The Haul · Dashboard** — GAP. No canonical `haul.dashboard`. **Option A (RECOMMENDED)**: reuse `gamification.getOverview` which returns `{ xp, level, streak, activeMissions, topBadges, leaderboardRank }` — identical shape. Adapter trivial.
- **061 The Haul · Missions** — CANONICAL → `gamification.getMissions` (wired).
- **062 The Haul · Mission Detail** — CANONICAL → `gamification.getMission`.
- **063 The Haul · Badges** — CANONICAL → `gamification.getBadges`.
- **064 The Haul · Leaderboard** — CANONICAL → `gamification.getLeaderboard` (wired).
- **065 The Haul · Streaks** — **GAP.** `gamification.getStreak` does NOT exist (verified via MCP). **Option A (RECOMMENDED)**: aggregate from `gamification.getProfile.currentStreak` plus derived history array computed from `gamification.getActivityLog` filtered by streak-qualifying events. **Option B**: compose `getProfile + getActivityLog + getMissions` to reconstruct timeline. **Option C**: ship read-only "Streak Week" card displaying only `currentStreak` and `bestStreak` until `gamification.getStreakHistory` ships in v1.1. (Recommended launch: Option C.)
- **066 The Haul · Cosmetics** — **GAP (structural).** `equipCustomization.ts` only supports `type='title'`. Frames, emotes, trailer skins, cab decals NOT backed. **Alternate**: hide Frames/Emotes/Trailer tabs behind feature flag (`cosmetics.frames.enabled=false`) until backend catches up; show only Titles tab with full RemoteState. Use `EusoEmptyState(comingSoon)` for hidden tabs with `TODO(backend: extend equipCustomization to accept type='frame'|'emote'|'trailer'|'decal')`.
- **067 The Haul · Store / Redeem** — PARTIAL → `rewards.redeem` exists but catalog endpoint `rewards.catalog` stubbed. Option B: compose catalog from `rewards.getFeatured` + `rewards.getRecommended` + local fallback JSON.
- **068 The Haul · XP History** — CANONICAL → `gamification.getActivityLog`.
- **069 The Haul · Season Pass** — GAP. Option C: defer to v2 with `EusoEmptyState(comingSoon)`.

### 070–079 Zeun (AI Copilot)
- **070 Zeun Home** — CANONICAL → `esangAI.getGreeting` + `esangAI.getSuggestions`.
- **071 Zeun Chat** — CANONICAL → `esangAI.chat` (streaming).
- **072 Zeun Voice** — CANONICAL → `esangAI.voice` (WebSocket).
- **073 Zeun Route Coach** — CANONICAL → `esangAI.routeCoach`.
- **074 Zeun Fuel Optimizer** — CANONICAL → `esangAI.fuelOptimize`.
- **075 Zeun Earnings Coach** — CANONICAL → `esangAI.earningsCoach`.
- **076 Zeun Safety Score** — CANONICAL → `safety.getScore` (`fmcsa_carrier_safety` adjacent).
- **077 Zeun Maintenance** — CANONICAL → `zeun.maintenance` (via `zeun_maintenance` MCP).
- **078 Zeun Mechanics · Report Issue** — CANONICAL → `zeunMechanics.reportBreakdown` (same endpoint as 043).
- **079 Zeun · ESANG Diagnose** — **GAP.** No dedicated diagnose endpoint. **Option A**: compose `esangAI.chat` with `context={type:'diagnose', vehicleId, symptoms[]}` — LLM handles branching. **Option B**: compose `zeunMechanics.getSymptomTree` + `esangAI.chat` + `zeun.maintenance.getHistory` — three-call compose on screen open. **Option C**: ship as "Ask Zeun about a breakdown" CTA opening 071 pre-seeded with diagnostic prompt template. **Recommended: Option A** — LLM context pattern already used by Route Coach, cheapest to ship.

### 080–089 Wallet, Settlement, Finance
- **080 Wallet Overview** — CANONICAL → `wallet.getOverview` (via `wallet_overview`).
- **081 Settlement Statements** — CANONICAL → `settlement.getOverview` (via `settlement_overview`).
- **082 Factoring Dashboard** — CANONICAL → `factoring.getOverview` (via `factoring_overview`).
- **083 Fuel Card** — CANONICAL → `fuel.getCard` + `fuel_surcharge_calc`.
- **084 Invoices (Broker/Shipper)** — CANONICAL → `invoices.list`.
- **085 Pay Now / Transfer** — CANONICAL → `payments.initiate`. **Financial guardrail**: no agent should execute; user confirms.
- **086 Tax Docs (1099, W-9)** — CANONICAL → `tax.getDocuments`.
- **087 Spending Analytics** — PARTIAL → rollup from `platform_analytics` + `wallet_overview`. Adapter required.
- **088 Credit Check (Broker)** — CANONICAL → `credit.check` (via `credit_check`).
- **089 Carrier Scorecard** — CANONICAL → `carrier.getScorecard` (via `carrier_scorecard`).

### 090–099 Cross-Border, Autonomous, Emergency, Misc
- **090 Cross-border · USMCA Cert** — CANONICAL → `crossBorder.usmca.generate` (within 186KB `crossBorder.ts`; verified via `cross_border_usmca`).
- **091 Cross-border · VUCEM / Pedimento** — CANONICAL → `crossBorder.vucem` (via `cross_border_vucem`).
- **092 Cross-border · Carta Porte** — CANONICAL → `crossBorder.cartaPorte` (inside `crossBorder.ts`).
- **093 Cross-border · ACE / ACI** — CANONICAL → `crossBorder.aceAci` (maps to MX/CA crossings MCP).
- **094 Cross-border · Crossings Live** — CANONICAL → `crossBorder.mxCrossings` (via `cross_border_mx_crossings`).
- **095 Cross-border · HOS (US/MX/CA harmonized)** — CANONICAL → `crossBorder.hos` (via `cross_border_hos`).
- **096 Autonomous · Fleet Monitor** — PARTIAL. `autonomous.ts` is 12KB — thin. `autonomous.getFleetStatus` exists and is enough for read-only monitor. See §3.
- **097 Autonomous · Handoff / Override** — **GAP (intentional).** Defer to v2. Recommended: ship 096 as "monitor" only; replace 097 with `EusoEmptyState(comingSoon)` titled "Handoff arrives in v2."
- **098 Emergency SOS** — CANONICAL → `emergencyResponse.triggerSOS` + `emergencyProtocols.getProtocol` (both exist; wire directly).
- **099 Settings · Profile / Preferences** — CANONICAL → `users.getMe` + `users.updatePreferences`.

---

## 3. High-friction screens — full redesign prescriptions

### 043 Exception · Breakdown
**Problem**: Figma proposes custom form POSTing to `breakdowns.report`, which does not exist.
**Fix**: wire directly to `zeunMechanics.reportBreakdown`. Existing endpoint accepts `{ vehicleId, symptoms[], severity, photos[], location }`. Map Figma fields 1:1.
**Glue**: `EusoTripAPI.shared.zeunMechanics.reportBreakdown(payload).withRemoteState(.loading|.success|.error)`.
**Offline fallback**: write to `OutboxQueue.breakdowns`, replay on reconnect.

### 044 Exception · Weather
**Status**: endpoint exists. Figma's mistake was proposing separate weather API. Wire to `weather.getRouteAlerts(loadId)` — returns `{ severity, windowStart, windowEnd, alternateRoute?, delayEstimate }`.
**Glue**: consume `RemoteState<WeatherAlerts>`; render top-severity alert in `EusoAlertBanner`.

### 048 Dispatch · Accept
**Status**: `drivers.acceptLoad(loadId)` exists. Figma ships double-confirm modal — correct for safety invariant. Wire directly; add optimistic UI with rollback on 4xx.

### 061 Missions / 064 Leaderboard
**Status**: wired. Confirm with iOS lead caching is `stale-while-revalidate` with 60s TTL (matches dispatcher pull-to-refresh expectation).

### 065 Streaks (RE-DESIGN REQUIRED)
**Recommendation**: ship **Streak Week** card (§2-065 Option C) for launch. Parallel track: open backend ticket for `gamification.getStreakHistory(range: 'week'|'month'|'season')`. Designer replaces placeholder with proper timeline chart in v1.1.
**Why not Option A/B immediately?** Derivation from `getActivityLog` is brittle — streak qualification rules encoded server-side in gamification reducer; client-side reconstruction will drift.

### 066 Cosmetics (SCOPE CUT)
**Prescription**: ship Titles tab only. Frames/Emotes/Trailer/Decal hidden behind `FeatureFlag.cosmeticsExpanded=false`. Figma adds single "More coming soon" tile to Titles tab footer with `sendPrompt("Notify me")` wired to `notifications.subscribe('cosmetics-expansion')`.

### 079 ESANG Diagnose
**Prescription**: Option A. Screen loads `esangAI.chat` with diagnostic context seed. Figma keeps current "symptom chips" but binds chip-tap to "append to prompt" rather than custom branch-tree call.
**Invariant check**: data provenance preserved (chat log audit-logged server-side); offline fallback shows `EusoEmptyState(offline)` because LLM requires network.

### 090–093 Cross-Border
**Verification**: every screen maps. `crossBorder.ts` (186KB) contains `usmca, vucem, cartaPorte, aceAci, mxCrossings, nom, mxTaxes, mxCompliance, caCompliance, baseRates, surcharges, trustedPrograms, pricing, currency, hos`. No gaps in this range.

### 096–097 Autonomous
**096**: ship as read-only "Fleet Monitor" consuming `autonomous.getFleetStatus`. No actions, only observability (truck positions, autonomy level, intervention count).
**097**: defer with `EusoEmptyState(comingSoon)`. Designer does NOT build handoff flow until `autonomous.requestHandoff` exists (backend ticket filed, v2).

### 098 Emergency SOS
**Prescription**: wire directly to `emergencyResponse.triggerSOS({ location, vehicleId, reason })` and, in parallel, hydrate protocol card from `emergencyProtocols.getProtocol(emergencyType)`. **SOS must work offline** — queue trigger to `OutboxQueue.priority='critical'` so it fires on first connectivity. Minimum viable offline: local 911 dialer fallback via `CallKit`.

---

## 4. Figma-to-canonical glue (recommended pattern)

Every screen must follow three-line pattern:

```swift
@StateObject var vm = ScreenVM(
    fetch: { try await EusoTripAPI.shared.<router>.<procedure>(args) }
)
// in View:
RemoteState(vm.state) { data in ScreenBody(data: data) }
```

`RemoteState` handles `.idle, .loading, .success(T), .empty, .error(E), .offline(cached: T?)`. Designers must produce Figma frame for each of the six states on every non-trivial screen. **Currently only 32 of 77 screens have all six states in Figma — single biggest design debt in queue.**

---

## 5. "Design works across the ecosystem" principle

Every alternate above filtered against four invariants:

1. **Driver's mental model.** If a screen shows a gauge, must match dashboard cluster metaphor driver sees in cab. No "dashboard" vs "overview" vs "summary" churn — we use "Today" for drivers, "Board" for dispatchers, "Overview" for everyone else.
2. **Backend data provenance.** Every number on screen must trace to a procedure. Client-side composition shows "Derived" micro-label in dev builds so QA knows.
3. **Offline-first fallback.** Every screen needs `.offline(cached:)` state. Rule: if a screen cannot meaningfully degrade, must not be on queue — drivers lose signal routinely.
4. **Accessibility.** WCAG 2.1 AA contrast, 44pt minimum touch targets, VoiceOver labels on every interactive element. Glove mode elevates to 88pt (2×). Night mode honors system appearance AND provides in-app quick-dim.

If any alternate breaks an invariant, rejected and bumped to v2.

---

## 6. Screens to DELETE (redundant)

- **023b "Splash with animation"** — duplicate of 023; splash is native, not a Figma screen.
- **030b "Driver Home (Map)"** — redundant. Map is tab within 030, not own screen.
- **036b "Notifications Filter"** — solved by sheet on 036; not standalone.
- **040b "Load List (Filters)"** — filter sheet lives inside 040.
- **050b "POD (Multiple Photos)"** — covered by 050 with photo-roll component.
- **067b "Store (Featured)"** — collapse into 067; tabs handle this.
- **071b "Zeun Chat (with Suggestions)"** — suggestions are banner on 071.
- **080b "Wallet (Transaction Detail)"** — make it a sheet from 080.

**Net reduction: 8 screens. Post-prune queue shrinks 77 → 69.**

---

## 7. Screens to ADD (gaps Figma missed)

### ADD-A · POD Signing · Landscape Split-Screen
Signature in portrait too cramped. Add dedicated landscape locking orientation, splitting screen into top BOL preview + bottom full-width signature canvas with `Clear` / `Accept`. Ties to existing `documents.attachSignature`. **P0.**

### ADD-B · Yard Jockey View
Terminal-yard role exists in `users.getMe.roles` but has no home screen. Needs dense ops view: spot map, move queue (`yard.getMoveQueue` exists), driver assignments. **P1.**

### ADD-C · Dispatch Bulk-Accept
Dispatchers routinely accept 5–20 loads in single session. Current 048 accepts one at a time. Add multi-select mode on 040 with bottom-action bar: "Accept 5 loads." Wire to new `loads.bulkAccept(ids[])`. Backend ticket required. **P1.**

### ADD-D · Night-Driving Quick-Dim
Single-tap toggle accessible from every screen's top-right — forces maximum dim, warm-shift, hides non-critical chrome. Complements system dark mode. No backend. **P0.**

### ADD-E · Glove-Mode UI
System-wide toggle doubling all touch targets to 88pt, thickening strokes, increasing minimum font size to 18pt. Single preference flag (`users.updatePreferences({ gloveMode: true })`). Designer produces "Glove Mode" Figma variant of every P0 screen. **P0.**

### ADD-F · SOS Protocol Briefing
098 triggers SOS; no screen for 10 seconds of "what's happening now" feedback. Needs dedicated live-status screen: dispatcher notified, ETA to responder, current vehicle geofence. Wires to `emergencyResponse.getStatus(incidentId)` (exists). **P0.**

### ADD-G · Detention Auto-Clock Confirm
Detention clock auto-starts at geofence entry (via `detention.open`) but driver sees no confirmation. Passive toast isn't enough — money on the line. Add 3-second interstitial: "Detention clock running." Wire to `detention.getTimer`. **P1.**

### ADD-H · POD Offline Queue Viewer
Drivers need to see which POD uploads stuck in outbox. Add screen listing queued uploads with retry/cancel affordances. Uses local `OutboxQueue` only — no new backend. **P1.**

### ADD-I · Zeun Listening Indicator (Always-On)
When `esangAI.voice` active, every screen should show subtle top-bar pulse — currently only 072 does. Not new screen, but system-wide component Figma library lacks. **P0.**

### ADD-J · Cross-Border Document Pre-Flight
Before crossing, drivers want single screen summarizing: USMCA cert ready, Carta Porte ready, ACE/ACI filed, HOS compliant. Composes `crossBorder.usmca.check + cartaPorte.check + aceAci.check + crossBorder.hos.check`. **P0 for cross-border drivers; P1 overall.**

**Net addition: 10 screens. Post-add queue: 69 + 10 = 79 screens.**

---

## 8. Priority stack

### P0 — Must ship before launch
023, 024, 025, 026, 027, 029, 030, 031, 035, 036, 040, 041, 042, 043, 044, 045, 046, 048, 050, 051, 052, 053, 054, 055, 056, 058, 059, 060 (via Option A), 061, 064, 070, 071, 080, 081, 083, 084, 085, 086, 089, 090, 091, 092, 093, 094, 095, 098, 099. Plus ADD-A, ADD-D, ADD-E, ADD-F, ADD-I, ADD-J for cross-border markets.
**Count: ~53.**

### P1 — Post-launch Wave 1 (weeks 2–8)
028, 032, 033, 034, 037, 038, 047, 049, 057, 062, 063, 065 (read-only card), 066 (Titles only), 067 (composed catalog), 068, 072, 073, 074, 075, 076, 077, 078, 079 (Option A), 082, 087, 088, 096 (monitor-only). Plus ADD-B, ADD-C, ADD-G, ADD-H.
**Count: ~30.**

### P2 — v2 and beyond
039 (theme toggle — system does it), 066 (Frames/Emotes/Trailer/Decal tabs), 069 (Season Pass), 097 (Autonomous handoff). Require new backend procedures or product decisions not yet made.
**Count: ~4.**

---

## 9. Figma source of truth

- **File**: `EusoTrip Mobile · Wave 1` (Figma URL pinned in SKILL.md §0).
- **Page structure**: one page per screen range — `023-029 Onboarding`, `030-039 Home`, `040-049 Loads`, etc.
- **Naming convention**: `[id] · [role-scope] · [screen-name] · [state]`. Example: `043 · driver · exception-breakdown · loading`. IDs three-digit zero-padded. Roles: `driver|dispatcher|broker|shipper|fleet-owner|yard-jockey|any`. States: `idle|loading|success|empty|error|offline`.
- **Component library**: `Euso Design System v2` — variables-only, no hardcoded colors or fonts. Every component maps to SwiftUI type in `EusoUI` package.
- **Versioning**: branches named `wave-1/*` for launch work; main frozen 48 hours before release.
- **Dev Mode links**: every frame must have "Dev Ready" status before entering SKILL.md §5 queue.

---

## 10. Handoff protocol

Every design change follows strict three-leg handoff to keep Figma, SKILL.md, routers in sync:

1. **Designer updates Figma.** Frame named per §9, marked "Dev Ready," all six RemoteState variants present. Designer tags iOS lead: `@ios-lead screen [id] ready for wiring`.
2. **iOS lead updates SKILL.md §5 queue.** Sets screen status `DESIGN → WIRING`, pins Figma URL, names expected procedure + RemoteState type. If backend doesn't exist, labels entry `NEEDS-BACKEND` and tags backend lead in PR description.
3. **Backend team updates router.** If alternate route is canonical (e.g., 065 Streaks → `getStreakHistory`), procedure added to appropriate router under `frontend/server/routers/`, test cases added in same PR, MCP tool regenerated so designers see in future audits.
4. **PR links to all three.** Every wiring PR includes: (a) Figma URL, (b) SKILL.md §5 diff, (c) router diff (or link to NEEDS-BACKEND ticket). Reviewers reject PRs missing any of three.
5. **Post-merge verification.** Product runs screen through `RemoteState` harness — every state must render without crash or visible placeholder. Failures bounce PR.

Any deviation surfaces as Figma-backend drift on next audit. Goal: zero drift.

---

## 11. Summary of actionable items

- **8 screens to delete** (redundant).
- **10 screens to add** (gaps, including landscape POD, glove mode, yard jockey, SOS briefing, cross-border pre-flight).
- **9 high-friction redesigns** documented in §3 with exact procedure bindings.
- **Post-audit queue: 79 screens** (from original 77, minus 8, plus 10).
- **P0 count: ~53. P1: ~30. P2: ~4.**
- **4 new backend procedures required**: `gamification.getStreakHistory`, `equipCustomization` (expand beyond `type='title'`), `loads.bulkAccept`, `autonomous.requestHandoff`. Backend tickets filed.
- **1 new router file permitted** (if needed): `cosmetics.ts` if `equipCustomization.ts` refactor exceeds 250 lines of diff.

`crossBorder.ts` (186KB) is most battle-tested piece of backend and covers every cross-border screen in queue. `gamification.ts` covers The Haul well except Streaks gap. `autonomous.ts` (12KB) is thinnest and justifies v2 deferral of 097. `emergencyResponse.ts + emergencyProtocols.ts` together sufficient for 098 + ADD-F.

This document is authoritative Figma-to-backend contract for Wave 1. Re-audited at end of every sprint. Any screen that drifts from canonical mapping (new Figma frame without procedure, or new procedure without frame) goes on drift ticket the following Monday.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
