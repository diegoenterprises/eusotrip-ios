# Wave-4 Build · Agent 05 · Theme 2.1 — `esangAI.getCoachCopy`

**Wave:** 4 (build spec, reviewed before landing in the web repo)
**Theme:** 2.1 · Per-surface ESANG "coach" copy (`_MASTER_ROADMAP.md` §2.1, attack order #5)
**Audit-run date:** 2026-04-18
**Affected screens:** ~60+ (every screen citing an "ESANG banner" / "ESANG suggests" / "AI narration" / "coach copy" surface in `_WAVE3_AUDIT/agent_0*.md`).
**Deliverable kind:** file diffs + two new files + one test file. APPEND-only on existing routers. NO edits to `server/routers.ts`, `drizzle/schema.ts`, or the `@eusotrip/api-contract` index — those edits are listed in §9 Changelog as follow-up tasks.

> Note on source tree: the mobile / SwiftUI tree in this repo (`EusoTrip/*`) is the consumer. The web-repo ("server/routers/...") paths cited below come from Wave-3 audit citations (`esangAI.ts:288+`, `esangAIv2.ts:66`, `esangVoiceOrchestrator.ts:159`, `hos.ts:50`, `driverMobile.ts:240/1496`, `weather.ts:149,363`, `loads.ts:*`). This doc is the landing spec that Wave-4 merges back into that repo.

---

## 1 · Goal (one sentence)

Add one tRPC v11 query `esangAI.getCoachCopy({ screen, context? }) → { primary, secondary?, cta? }` that fans in real driver context (HOS, active load, weather) and returns ready-to-render coach copy, with a 60 s cache so ~60 mobile screens can drop the static LLM callouts onto a real endpoint without rewriting the chat infra.

## 2 · Call signature (locked)

```ts
// Input
z.object({
  screen: z.string().min(3).max(64),              // e.g. "010_DriverHome", "039_BackingAssistReceiver"
  context: z.record(z.unknown()).optional(),      // optional screen-local overrides (loadId, stopId, trailerId, facilityId, ...)
})

// Output
{
  primary: string;                                 // ~60 chars headline, required
  secondary?: string;                              // ~140 chars sub-copy, optional
  cta?: { label: string; action: string } | null;  // null if no CTA, action = client-route/intent id
  meta: {
    screen: string;
    cacheHit: boolean;
    generatedAt: string;                           // ISO 8601 UTC
    ttlSec: number;                                // echo of 60
    model: string;                                 // e.g. "claude-sonnet-4-esang-v2"
    promptVersion: string;                         // from esangCoachPrompts.ts
  };
}
```

Schema lives beside the router (exported from `esangAI.ts` so consumers can import the `GetCoachCopyOutput` type). **No `schema.ts` / api-contract index changes in this wave** — the type crosses the wire via tRPC inference, which is how every other procedure in `esangAI.ts` exports its shape. The explicit api-contract re-export is queued in §9 Changelog.

## 3 · Files touched

| # | Path | Change | Size |
|--:|---|---|---:|
| 1 | `server/routers/esangAI.ts` | **APPEND** one procedure below the last `}` of the router object | ~85 lines |
| 2 | `server/routers/esangCoachPrompts.ts` | **NEW** — prompt table + `renderSystemPrompt` helper | ~420 lines |
| 3 | `server/routers/__tests__/esangCoachCopy.test.ts` | **NEW** — unit + integration + cache tests | ~260 lines |

Explicitly not touched in this wave: `server/routers.ts`, `drizzle/schema.ts`, `@eusotrip/api-contract/index.ts`, `esangAIv2.ts`, `esangVoice.ts`, `esangVoiceOrchestrator.ts`.

## 4 · Which existing procedures we call (all cited back to Wave-3 audit)

| Context field | Source procedure | Cited in | Notes |
|---|---|---|---|
| HOS (drive left, window left, cycle left, duty status, next reset) | `hos.getCurrentStatus` | `hos.ts:50` (agent_00.md:20, 22, 262; agent_02.md:40, 311) | Primary HOS read. Already `protectedProcedure`, returns `{ driveRemainingMin, windowRemainingMin, cycleRemainingMin, dutyStatus, nextResetAt }`. |
| Active load (origin, dest, stop, UN #, appt window) | `driverMobile.getDriverHomeDashboard` | `driverMobile.ts:240` (agent_00.md:17; agent_04.md:81) | Aggregator returns `{ activeLoad, nextStop, hosSnapshot, trailer }` — cheapest single fetch. We read `activeLoad` + `nextStop` only. |
| Route weather on current leg | `weather.getDriverRouteWeather` | `weather.ts:363` (agent_02.md:42) | Returns `{ hazards: [{ kind, severity, etaMin, mitigation }], advisory }`. |
| Fallback HOS (team-driver / detailed) | `driverMobile.getDriverHosStatus` | `driverMobile.ts:1496` (agent_00.md:262) | Used only if `hos.getCurrentStatus` returns `null` (non-driver ctx). |
| Screen-specific extras — opt-in, chosen by prompt table | `loadLifecycle.getActiveTimers` (`loadLifecycle.ts:3175`), `navigation.getETA` (`navigation.ts:123`), `reeferTemp.getReadings` (`reeferTemp.ts:19`), `tankMonitor.*` | agent_00.md:136, 201, 287; agent_02.md:369 | Each prompt config declares which of these it needs; the fetch layer only calls what the prompt requires. |

All four of these exist and are already `protectedProcedure` — no extra auth plumbing. We invoke them via the **server-side tRPC caller** (`ctx.trpc.caller ??= appRouter.createCaller(ctx)` — pattern already used in `esangAIv2.chat` per `esangAIv2.ts:66`, cited in agent_06.md:127). If that caller instance is not yet on ctx, we use `appRouter.createCaller(ctx)` directly (same technique as `esangVoiceOrchestrator.generateVoicePrompts` at `esangVoiceOrchestrator.ts:159`, cited in agent_08.md:24).

## 5 · Cache layer — reuse, don't invent

Audit cites no top-level `ioredis` import in `esangAI.ts`, but the web repo already ships a Redis wrapper used by `rateLimiter.ts` and `sessionStore.ts` (discovery task queued in §9). **Strategy:**

1. First resolve `ctx.redis` (the convention every other router in the repo uses per the Wave-3 reports). If truthy, use it with key `esang:coach:v1:{screen}:{driverId}:{hash}` and `SET ... EX 60`.
2. If `ctx.redis` is null/undefined in a test or local-dev environment, **fall back to an in-memory LRU of size 1 024** via the existing `lru-cache` dep (this repo already ships `lru-cache` because `navigation.ts` and `weather.ts` cache polylines with it per agent_00.md:136, agent_02.md:42 context). If that dep is somehow not yet in `package.json`, we dynamic-require it and, on throw, fall through to a `Map` with FIFO-128 eviction. **Noted in §9 Changelog as a follow-up audit task, not a new dep.**
3. Cache key = `esang:coach:v1:${screen}:${driverId}:${hashOfContext}` where `hashOfContext` = `sha1(JSON.stringify(contextSorted)).slice(0, 12)`.
4. TTL = 60 s. Response includes `meta.cacheHit` so clients can debug.
5. Invalidation: explicit `invalidateCoachCopy(driverId)` helper exported for future `loadLifecycle.executeTransition` hooks (Theme 2.2). Not called from anywhere this wave — Theme 2.2 wires it.

No streaming / socket.io in this procedure. Roadmap §2.1 mentions socket.io "for live panels (081, 053)" — that is out of scope for this wave; see §9.

## 6 · Prompt table — `server/routers/esangCoachPrompts.ts` (new file)

Structure:

```ts
export type ScreenId =
  | "010_DriverHome"
  | "011_PretripDVIR"
  | "013_ActiveEnroute"
  | "014_ApproachingPickup"
  | "015_AtGateAwaitingDock"
  | "016_PickupLoading"
  | "017_PickupBolSigning"
  | "018_ActiveEnrouteLoaded"
  | "019_HosDutyStatus"
  | "020_ApproachingDelivery"
  | "021_AtReceiverGate"
  | "022_DockAssigned"
  // Bucket 01 — tanker lifecycle (audit: agent_01.md)
  | "023_BackingIn" | "024_Unloading" | "025_PostTripDvir" | "026_ShiftEnd"
  | "027_OverviewDashboard" | "028_TripsList" | "029_YardQueue" | "030_TankerPickup"
  | "031_LoadVerdict" | "032_Detach" | "033_DetachCompleted" | "034_LoadLocked"
  | "035_LoadLockedFilled"
  // Bucket 02 — in-bay wizards (audit: agent_02.md)
  | "036_SmartStop" | "037_Routing" | "038_FacilityDetail" | "039_BackingAssistReceiver"
  | "040_Discharge" | "041_DischargeProgress" | "042_Disconnect" | "043_DisconnectConfirmed"
  | "044_ConnectDropHose" | "045_SealBreak" | "046_SealApplied" | "047_KioskScan"
  | "048_ArrivalGateTaskActive"
  // Bucket 03 — hazmat + spectra (audit: agent_03.md)
  | "049_SpectraMatch" | "050_SpectraRun" | "051_SpectraVerdict" | "052_RateConfirm"
  | "053_DispatchChat" | "054_HaulPaySettlement" | "055_DayCloseWallet" | "056_HazmatPool"
  | "057_HazmatReadiness" | "058_HazmatReview" | "059_HazmatIncident"
  | "060_HazmatPoolRoster" | "061_HazmatPoolDetail"
  // Bucket 04 — feedback / gamification (audit: agent_04.md)
  | "062_Feedback" | "063_Ratings" | "064_NotificationsInbox" | "065_EusoTicketException"
  | "066_FeedbackRatings" | "067_TheHaulMission" | "068_TheHaulLeaderboard"
  | "069_AchievementsWall" | "070_InviteDriver"
  // Bucket 05 — schedule / compliance (audit: agent_05.md)
  | "071_DailyStreak" | "072_Training" | "073_Tax1099" | "074_NotificationCenter"
  | "075_Preferences" | "076_Privacy" | "077_HomeSchedule"
  // Bucket 06 — availability / roadside / earnings (audit: agent_06.md)
  | "078_HomeCompliance" | "079_Maintenance" | "080_MaintenanceDetail" | "081_EsangChat"
  | "082_VoiceInbox" | "083_ScheduleAvailability" | "084_WeeklySummary" | "085_TelemetrySnapshot"
  | "086_RoadsideInspection" | "087_EarningsOverview" | "088_EarningsWeekly" | "089_EarningsDetail"
  // Bucket 07 — wallet / claims (audit: agent_07.md)
  | "090_WalletHome" | "091_WalletCards" | "092_SettlementDetail" | "093_TaxVault"
  | "094_ClaimsHome" | "095_Notifications" | "096_ClaimOpen" | "097_ClaimEvidence"
  | "098_ClaimClosed" | "099_LaneRadar" | "100_LaneRadarDetail" | "101_TrailerTelemetry"
  | "102_EusoTicketList"
  // Bucket 08 — inbox / advisory (audit: agent_08.md)
  | "103_FuelPlanner" | "104_FuelAdvisor" | "105_DvirAdvisor" | "106_SafetyCoach"
  | "107_Roadside" | "108_LoadMatchAdvisor" | "109_InboxOverview" | "110_InboxFilters"
  | "111_MessagesList" | "112_Inbox" | "113_Thread" | "114_Broadcasts" | "115_VoiceReply"
  // Bucket 09 — routing / reroute (audit: agent_09.md)
  | "116_RouteOverview" | "117_Reroute" | "118_FuelPriceLock" | "119_TankStatus";

export interface SystemPromptConfig {
  system: string;              // persona + tone + structural rules
  user: string;                // user-template w/ {{placeholders}}
  needs: {
    hos?: boolean;
    activeLoad?: boolean;
    routeWeather?: boolean;
    activeTimers?: boolean;
    eta?: boolean;
    reefer?: boolean;
    tank?: boolean;
  };
  maxTokens: number;           // 128 default; 192 for long-form advisors
  temperature: number;         // 0.4 default; 0.6 for 081_EsangChat preview
  tone: "concise" | "warm" | "urgent";
  ctaIntents?: string[];       // allow-listed action ids the LLM may return
}

export const PROMPT_VERSION = "esang-coach-prompts/2026.04.18-a";

export const COACH_PROMPTS: Record<ScreenId, SystemPromptConfig> = {
  "010_DriverHome": {
    system:
      "You are ESANG, a calm in-cab coach for a U.S. commercial trucker. You speak in short, confident sentences. You never repeat HOS numbers back to the driver — you translate them into an action. Never use exclamation points. Never mention you are an AI.",
    user:
      "Driver {{driverFirstName}} is on DriverHome. Active load: {{load.origin}} -> {{load.dest}} ({{load.commodity}}). HOS: drive {{hos.driveRemainingMin}}m / window {{hos.windowRemainingMin}}m / cycle {{hos.cycleRemainingMin}}m. Next stop: {{stop.name}} at {{stop.apptWindow}}. Weather ahead: {{weather.summary}}. Write a 1-line primary nudge (<=60 chars), a 1-line secondary (<=140 chars), and a CTA from this list or null: [resumeMap, startPretrip, reviewHos, openStop].",
    needs: { hos: true, activeLoad: true, routeWeather: true },
    maxTokens: 128,
    temperature: 0.4,
    tone: "concise",
    ctaIntents: ["resumeMap", "startPretrip", "reviewHos", "openStop"],
  },
  "013_ActiveEnroute": {
    system: "You are ESANG. Driver is rolling. Be short and forward-looking.",
    user:
      "ETA {{eta.minutes}}m to {{stop.name}}. HOS drive left {{hos.driveRemainingMin}}m. Weather: {{weather.summary}}. One-line nudge, optional 1-line secondary, CTA from [takeBreak, continue, reroute, callShipper] or null.",
    needs: { hos: true, activeLoad: true, routeWeather: true, eta: true },
    maxTokens: 128,
    temperature: 0.4,
    tone: "concise",
    ctaIntents: ["takeBreak", "continue", "reroute", "callShipper"],
  },
  // ... (115 entries total, one per ScreenId)
  // Pattern for advisory screens (104_FuelAdvisor, 106_SafetyCoach, 108_LoadMatchAdvisor)
  // uses tone "warm", maxTokens 192, and temperature 0.55.
  // Pattern for urgent screens (032_Detach, 039_BackingAssistReceiver, 040_Discharge, 042_Disconnect,
  // 059_HazmatIncident, 086_RoadsideInspection, 117_Reroute) uses tone "urgent", temperature 0.3,
  // and ctaIntents confined to stop/abort/confirm verbs.
  //
  // (Full table materialized in the landed file; truncated here for review. Each entry must:
  //   - cite its source row from the Wave-3 audit in a leading // comment,
  //   - declare only the `needs` it actually interpolates,
  //   - pick ctaIntents from the union matching its screen's UI affordances.)
};

export function renderSystemPrompt(
  screen: ScreenId,
  ctx: CoachCtx,            // typed fan-in bundle built by the fetch layer
  overrides?: Record<string, unknown>,
): { system: string; user: string; cfg: SystemPromptConfig } { /* ... */ }
```

Rules for the full table (enforced in the unit test):

1. Every `ScreenId` key is present exactly once.
2. Every placeholder token in `user` has a corresponding field in the fan-in bundle OR in `overrides`.
3. `ctaIntents` are drawn from the app's known client-route/intent registry (Wave-4 Theme 2.2 publishes the canonical list; this wave embeds the subset for the 115 entries and comments `// TODO(theme-2.2): dedupe against canonical intent registry when published`).
4. No placeholder interpolates raw PII — only first name, load ids, screen-safe strings.

## 7 · Procedure skeleton — appended to `esangAI.ts`

```ts
// -------------------------------------------------------------------
// Theme 2.1 (Wave-4) — per-surface coach copy
// APPEND-ONLY: do not edit lines 1..<last-existing-line> of this file.
// -------------------------------------------------------------------
import crypto from "node:crypto";
import { TRPCError } from "@trpc/server";
import { COACH_PROMPTS, PROMPT_VERSION, renderSystemPrompt, type ScreenId }
  from "./esangCoachPrompts";

const GetCoachCopyInput = z.object({
  screen: z.string().min(3).max(64),
  context: z.record(z.unknown()).optional(),
});

const GetCoachCopyOutput = z.object({
  primary: z.string(),
  secondary: z.string().optional(),
  cta: z
    .object({ label: z.string(), action: z.string() })
    .nullable()
    .optional(),
  meta: z.object({
    screen: z.string(),
    cacheHit: z.boolean(),
    generatedAt: z.string(),
    ttlSec: z.number(),
    model: z.string(),
    promptVersion: z.string(),
  }),
});
export type GetCoachCopyOutput = z.infer<typeof GetCoachCopyOutput>;

// Appended inside the existing `esangAI = router({ ... })` object.
// Implementation summary:
//
// 1. Reject unknown screen ids (screen not in COACH_PROMPTS) with
//    TRPCError code: "BAD_REQUEST", message: "Unknown ESANG screen id".
// 2. Build cache key: `esang:coach:v1:${screen}:${driverId}:${hashOfCtx}`.
//    hashOfCtx = sha1(stableStringify(input.context ?? {})).slice(0,12).
// 3. Try cache (ctx.redis ?? in-mem LRU). On hit, return with meta.cacheHit=true.
// 4. Build ctx bundle. Fetch only the procedures that cfg.needs declares:
//      - hos: hos.getCurrentStatus (falls back to driverMobile.getDriverHosStatus)
//      - activeLoad: driverMobile.getDriverHomeDashboard (we read .activeLoad + .nextStop)
//      - routeWeather: weather.getDriverRouteWeather
//      - eta: navigation.getETA
//      - activeTimers: loadLifecycle.getActiveTimers
//      - reefer: reeferTemp.getReadings
//      - tank: tankMonitor.getLoadingSnapshot  (if Theme 2.4 has landed)
//    Each fetch is wrapped in Promise.allSettled so one failing dep
//    degrades to cached-substitution / "unknown" placeholders, never 500.
// 5. Call ctx.llm.complete({ system, user, maxTokens, temperature, stop:["\n\n"] }).
//    ctx.llm is the existing client already used by esangAIv2.chat (esangAIv2.ts:66).
//    Parse JSON response — if parse fails, fall back to the prompt's
//    deterministic template ("fallback primary" baked into each entry).
// 6. Validate LLM output against GetCoachCopyOutput (minus meta) and
//    coerce cta.action into cfg.ctaIntents (strip if not allow-listed).
// 7. Cache the final object for 60 s.
// 8. Emit `logger.info({ screen, driverId, cacheHit, latMs })` for dashboards.
//
// All together:

getCoachCopy: protectedProcedure
  .input(GetCoachCopyInput)
  .query(async ({ ctx, input }): Promise<GetCoachCopyOutput> => {
    const cfg = COACH_PROMPTS[input.screen as ScreenId];
    if (!cfg) {
      throw new TRPCError({ code: "BAD_REQUEST", message: "Unknown ESANG screen id" });
    }
    const driverId = ctx.user.id;
    const ctxHash = crypto
      .createHash("sha1")
      .update(stableStringify(input.context ?? {}))
      .digest("hex")
      .slice(0, 12);
    const key = `esang:coach:v1:${input.screen}:${driverId}:${ctxHash}`;

    const cached = await coachCache.get(ctx, key);
    if (cached) {
      return { ...cached, meta: { ...cached.meta, cacheHit: true } };
    }

    const bundle = await fetchCoachBundle(ctx, cfg.needs, input.context);
    const { system, user } = renderSystemPrompt(input.screen as ScreenId, bundle, input.context);

    const raw = await ctx.llm.complete({
      system,
      user,
      maxTokens: cfg.maxTokens,
      temperature: cfg.temperature,
      stop: ["\n\n"],
    });

    const parsed = safeParseCoachJson(raw) ?? fallbackCopy(cfg, bundle);
    const cta = parsed.cta && cfg.ctaIntents?.includes(parsed.cta.action) ? parsed.cta : null;

    const out: GetCoachCopyOutput = {
      primary: parsed.primary,
      secondary: parsed.secondary,
      cta,
      meta: {
        screen: input.screen,
        cacheHit: false,
        generatedAt: new Date().toISOString(),
        ttlSec: 60,
        model: ctx.llm.modelId ?? "esang-default",
        promptVersion: PROMPT_VERSION,
      },
    };

    await coachCache.set(ctx, key, out, 60);
    return out;
  }),
```

Helpers `coachCache`, `fetchCoachBundle`, `safeParseCoachJson`, `fallbackCopy`, `stableStringify` live at the bottom of the appended block (private to this file — not exported from the router).

## 8 · Tests — `server/routers/__tests__/esangCoachCopy.test.ts`

Test targets (vitest, mirrors the repo's existing router test style):

1. **Happy path · 010_DriverHome.** Mock `ctx.llm.complete` to return valid JSON. Assert output shape, `meta.cacheHit === false`, `meta.promptVersion === PROMPT_VERSION`.
2. **Cache hit on second call.** Same `(screen, driverId, context)` → second call does not invoke `ctx.llm.complete` and returns `cacheHit: true`.
3. **Cache miss on context change.** Same screen + driver but `context.loadId` differs → second call re-invokes the LLM.
4. **Unknown screen rejects.** `screen: "999_Bogus"` → `TRPCError` code `BAD_REQUEST`.
5. **CTA allow-list enforcement.** LLM returns `cta.action: "launchRocket"` → output's `cta` is `null`.
6. **LLM JSON parse failure → fallback.** LLM returns `"not json"` → `primary` equals the screen's hard-coded fallback string; call still succeeds.
7. **Context fetch degradation.** `weather.getDriverRouteWeather` throws → `Promise.allSettled` swallows it, prompt renders with `weather.summary = "unknown"`, no 500.
8. **Prompt table completeness.** `expect(Object.keys(COACH_PROMPTS).length).toBeGreaterThanOrEqual(115)` AND every `ScreenId` in the union has an entry.
9. **Placeholder-coverage lint.** For each prompt, extract `{{x.y}}` tokens and assert every token resolves from `cfg.needs` sources or is declared optional.
10. **Caller wiring.** `appRouter.createCaller` route — end-to-end protectedProcedure auth check (anon ctx rejects with `UNAUTHORIZED`).

Mocks: a `makeMockCtx()` factory returns `{ user, redis: null, llm: { complete: vi.fn(), modelId: "test" }, trpc: { caller: stubCaller } }`. `stubCaller` returns fixed HOS / load / weather shapes per test.

## 9 · Changelog · follow-up edits this wave intentionally defers

These edits are **out of scope for Wave-4 Agent-05** per the strict-rules section, but they must be opened as follow-up tasks before ship:

1. **`server/routers.ts`** — no edit needed if `esangAI` is already re-exported as a sub-router (audit cites `esangAI.ts` as a router file; it must already be wired). Verify during review; if missing, open a one-line follow-up PR to add `esangAI` to the root router map.
2. **`@eusotrip/api-contract/index.ts`** — re-export `GetCoachCopyOutput` alongside the other `esangAI` types so SwiftUI code-gen picks it up. Open as follow-up; does not block the server-side ship because tRPC inference covers TS clients.
3. **`drizzle/schema.ts`** — no schema changes in this wave. Theme 2.2 will add a `coach_copy_events` hypertable (driver, screen, latency, cacheHit, tokenCount) for observability; spec'd separately.
4. **Redis/LRU audit.** Confirm `ctx.redis` convention and that `lru-cache` is already in `package.json`. If not, the agent landing this diff is authorized to add `lru-cache@^10` (already transitively present via `trpc` tooling in most repos) — no new deps otherwise.
5. **Socket.io streaming** for 081 ESANG Chat / 053 Dispatch Chat (roadmap §2.1 aspiration) — **deferred to Wave-5**. `getCoachCopy` is a `.query` only; the streaming surface will wrap it.
6. **Invalidation hook** — Theme 2.2 (loadLifecycle) must call `invalidateCoachCopy(driverId)` on every state transition. Exported by this wave but not wired.
7. **Prompt table full materialization.** The spec above shows 2 complete entries + placeholder comment for 113 more. The landing PR must contain all 115; reviewers should diff `Object.keys(COACH_PROMPTS)` against the ScreenId union.
8. **Rate limiting.** `esangAIv2.chat` already uses the shared rate limiter per `esangAIv2.ts:66` (agent_06.md:127). `getCoachCopy` should reuse the same bucket key scheme (`driverId:esangAI:*`) — verify during review.
9. **SwiftUI binding.** Mobile client update is a Wave-5 task; the 60+ screens currently render hard-coded strings. Port plan: add `EsangCoachCopy` struct in `EusoTripAPI.swift`, a `@Observable CoachCopyStore` keyed on `(screen, context)` with a 60s in-memory mirror.

## 10 · Risks + mitigations

| Risk | Mitigation |
|---|---|
| LLM latency breaks render (Driver Home renders < 150 ms p50). | 60 s cache → first-after-login is the only slow path. Fallback copy handles timeout (2 s LLM deadline). |
| Prompt table drift vs ScreenId union. | TS union + `Record<ScreenId, ...>` gives compile-time completeness; test 8 doubles it at runtime. |
| LLM hallucinates CTA. | Allow-list filter in step 6 of the handler strips any non-registered `action`. |
| Cache-key collision across drivers. | Key includes `driverId`; `ctxHash` is the second axis. Not shared globally. |
| Redis not configured in dev. | In-mem LRU fallback + explicit `meta.cacheHit` in payload so QA can spot it. |
| PII in prompts. | `renderSystemPrompt` only interpolates whitelisted fields (first name, load ids, commodity, window strings). No phone, no full name, no address beyond stop name. Unit test 9 asserts the whitelist. |

## 11 · Acceptance

- [ ] `esangAI.getCoachCopy` appears in the tRPC router tree and is a `.query` of `protectedProcedure`.
- [ ] `server/routers/esangCoachPrompts.ts` exports `COACH_PROMPTS`, `PROMPT_VERSION`, `renderSystemPrompt`, and type `ScreenId` with at least 115 entries.
- [ ] Test file passes all 10 cases above on CI.
- [ ] No lines in `esangAI.ts` above the append boundary were modified.
- [ ] No changes in `server/routers.ts`, `drizzle/schema.ts`, `@eusotrip/api-contract/index.ts`.
- [ ] `meta.cacheHit` is observable on the wire for QA.
- [ ] Reviewer signs off on the 115-entry prompt table before merge.

---

**Agent-05 report ends.** Hand-off to reviewer + Theme-2.2 agent (who owns `invalidateCoachCopy` wiring).
