# Wave-4 Build · Agent 04 · Theme 2.3 — `bayOps/` routers

**Date:** 2026-04-18
**Roadmap reference:** `_WAVE3_AUDIT/_MASTER_ROADMAP.md` § 2.3
**Bucket report:** `_WAVE3_AUDIT/agent_02.md` (screens 039–044)
**Status:** Implemented — pending schema merge + root-router wiring (see **Required downstream edits** below).

---

## 1 · Files delivered

| Path | Purpose |
|---|---|
| `server/routers/bayOps/_shared.ts` | Common FSM machinery: session map keyed on `${kind}:${loadId}`, guard helpers, `persistEvent`, `buildWizardRouter` factory. |
| `server/routers/bayOps/discharge.ts` | FSM `arm → purge → meter → seal` (seal terminal). |
| `server/routers/bayOps/disconnect.ts` | FSM `blowdown → break → cap → photo` (photo terminal). |
| `server/routers/bayOps/connectHose.ts` | FSM `grounding → coupling → pressureTest` (pressureTest terminal). |
| `server/routers/bayOps/backingAssist.ts` | FSM `align → approach → engage → secured` + `recordDistanceSample`, `recordTelemetry`, `hasActiveSession`. |
| `server/routers/bayOps/index.ts` | Grouped `bayOpsRouter` + `BAY_OPS_FSMS` export. |
| `drizzle/schema.additions.wave4-4.ts` | `bayOpsEvents` table (Drizzle) with composite indexes. |
| `drizzle/0130_bayops.sql` | SQL migration (plain Postgres) — table + 2 indexes. |
| `server/routers/__tests__/bayOps.test.ts` | Vitest suite: FSM shape, happy paths, guard rails, telemetry. |

Total: **9 new files, 0 edits to locked files.**

---

## 2 · Public surface — every wizard exposes

| Procedure | Auth | Shape |
|---|---|---|
| `getSession` | `roleProcedure(['DISPATCHER','DRIVER'])` | `{ loadId } → { session, history[] }` |
| `start` | `roleProcedure(['DRIVER'])` | `{ loadId, context? } → { session }` |
| `advanceStep` | `roleProcedure(['DRIVER'])` | `{ loadId, toStep, payload? } → { session }` |
| `recordEvidence` | `roleProcedure(['DRIVER'])` | `{ loadId, step, s3Key, kind, note? } → { eventId, step }` |
| `complete` | `roleProcedure(['DRIVER'])` | `{ loadId, payload? } → { session }` — rejects if current step is non-terminal |
| `abort` | `roleProcedure(['DRIVER'])` | `{ loadId, reason } → { session }` |

**`backingAssist` additions:**
- `recordDistanceSample({ loadId, rearIn, leftClearanceIn?, rightClearanceIn?, sensorSource })` — ultrasonic/LiDAR/camera-AI sample; returns `shouldPromptEngage` hint when `rearIn ≤ 4`.
- `recordTelemetry({ loadId, frame, clipS3Key? })` — generic telemetry frame with optional S3 clip key.
- `hasActiveSession({ loadId })` — lightweight bool probe.

---

## 3 · FSM tables (source of truth — TypeScript, not DB)

```ts
// discharge
{ arm: ['purge'], purge: ['meter'], meter: ['seal'], seal: [] }
// disconnect
{ blowdown: ['break'], break: ['cap'], cap: ['photo'], photo: [] }
// connectHose
{ grounding: ['coupling'], coupling: ['pressureTest'], pressureTest: [] }
// backingAssist
{ align: ['approach'], approach: ['engage'], engage: ['secured'], secured: [] }
```

All four are linear today. Branching (e.g. `break → blowdown` retry) is intentionally deferred — the roadmap's screens 042/043 don't show a back-step, and the FSM guard already rejects unknown transitions so adding branches later is additive.

---

## 4 · Persistence model

Append-only `bay_ops_events`:

| Column | Type | Notes |
|---|---|---|
| `id` | `uuid` PK | `gen_random_uuid()` default. |
| `load_id` | `uuid` NN | |
| `wizard_kind` | `text` NN | `CHECK IN ('discharge','disconnect','connectHose','backingAssist')` |
| `step` | `text` NN | Current FSM step at event time. |
| `payload` | `jsonb` NN | Discriminator `phase ∈ start\|advance\|evidence\|complete\|abort\|distance\|telemetry`. |
| `evidence_s3_key` | `text` NULL | Presigned-URL upload happens elsewhere; router only persists the key. |
| `created_at` | `timestamptz` NN | |
| `created_by_driver_id` | `uuid` NN | |

Indexes:
- `(load_id, wizard_kind)` — replay one wizard for one load.
- `(created_by_driver_id, created_at DESC)` — per-driver audit feed.

---

## 5 · Design decisions

1. **Sessions live in memory (`Map`)**, not in the DB — a bay-ops session is inherently ephemeral and we already persist every transition as an event. On crash/restart the client re-hydrates via `getSession` (history) and can decide whether to abort & restart.
2. **Single session per `(loadId, kind)`** — attempting a second `start` throws `CONFLICT`. Parallel wizards of *different* kinds on the same load are allowed (e.g. `backingAssist` + `discharge` on separate loads/legs).
3. **`complete` requires a terminal step.** Non-terminal completion throws `FAILED_PRECONDITION`.
4. **No database-side enum for `wizard_kind`** — kept as text with a check constraint so adding a 5th wizard later is a one-line migration.
5. **Role enforcement centralised.** All mutations → `roleProcedure(['DRIVER'])`; reads → `roleProcedure(['DISPATCHER','DRIVER'])`. Dispatcher write attempts return `FORBIDDEN` in the test suite.
6. **Evidence is key-only.** Upload pipeline (presigned PUT → S3) lives in the separate `uploads/` router; we only persist the returned key.

---

## 6 · Required downstream edits (NOT performed — locked files)

These four edits must land in a follow-up PR before the routers can be served:

### 6.1 `server/routers.ts` (or root router barrel)
```ts
import { bayOpsRouter } from './routers/bayOps';

export const appRouter = router({
  // ...existing...
  bayOps: bayOpsRouter,
});
```

### 6.2 `drizzle/schema.ts`
Merge `drizzle/schema.additions.wave4-4.ts` into the main schema. Recommended spot: immediately after the `custodyChain*` / `loadLifecycle*` tables so a `grep bay_ops` lands next to related transitions.

### 6.3 api-contract index (`api-contract/index.ts` or equivalent)
Append the four sub-routers so generated client types pick them up:
```ts
export type BayOpsRouter = AppRouter['bayOps'];
export type DischargeRouter = BayOpsRouter['discharge'];
export type DisconnectRouter = BayOpsRouter['disconnect'];
export type ConnectHoseRouter = BayOpsRouter['connectHose'];
export type BackingAssistRouter = BayOpsRouter['backingAssist'];
```

### 6.4 `drizzle/meta/_journal.json`
Register migration `0130_bayops.sql`. Standard drizzle-kit `generate` will do this automatically on next schema merge.

---

## 7 · Integration with `loadLifecycle.ts`

`bayOps` is deliberately orthogonal to the lifecycle FSM. The relationship:

| loadLifecycle.loadStatus | expected live bayOps wizard(s) |
|---|---|
| `delivery_checkin` | `backingAssist`, then `connectHose` |
| `unloading` | `discharge` |
| `unloaded` | `disconnect` |

When `loadLifecycle.executeTransition` flips status to one of the above it's the *client's* responsibility to call `bayOps.<kind>.start`. The server does not auto-start wizards — Wave-3 audit flagged this as intentional to preserve operator-initiated control. A future enhancement could add a dispatcher-only `bayOps.<kind>.startOnBehalf` for remote triage.

---

## 8 · Tests (`server/routers/__tests__/bayOps.test.ts`)

Vitest suite covers:
- **FSM shape invariants** — every referenced step is declared; each FSM has exactly one terminal node.
- **Happy paths** for all four wizards end-to-end (`start` → `advanceStep` × N → `complete`).
- **Guard rails** — illegal transition, double-start, parallel kinds allowed, complete-before-terminal, abort path, dispatcher-mutation forbidden, dispatcher-read allowed, evidence without FSM movement.
- **Telemetry** — `recordDistanceSample` engage-prompt threshold, `recordTelemetry` with clip key, `hasActiveSession` false, telemetry without a running session → `NOT_FOUND`.

DB and tRPC are mocked locally to keep the suite unit-level and fast. Swap to the real testcontainers harness when Wave-4 merges schema additions into `schema.ts`.

---

## 9 · Wave-3 audit GAPs resolved (from `agent_02.md`)

| GAP | Screen | Resolved by |
|---|---|---|
| `backingAssist.*` router entirely missing | 039 | `server/routers/bayOps/backingAssist.ts` |
| `discharge.*` / `transferSession.*` missing | 040 / 041 | `server/routers/bayOps/discharge.ts` |
| `disconnectWizard.*` FSM missing | 042 / 043 | `server/routers/bayOps/disconnect.ts` |
| `connectWizard.*` FSM missing | 044 | `server/routers/bayOps/connectHose.ts` |
| Camera / ultrasonic / LiDAR ingestion surface missing | 039 | `backingAssist.recordDistanceSample` + `recordTelemetry` |
| No evidence link for bay ops | 039–044 | `recordEvidence` + `evidence_s3_key` column |

Out of scope (flagged for later themes):
- Live sensor *streaming* (WebSocket / MQTT) — Theme 2.4 telemetry bus.
- Spotter voice channel — Theme 3.x communicationHub.
- Facility dock-receipt ack (screen 043) — Theme 2.6 yard/facility.
- ESANG AI co-signature hash — Theme 4.x blockchainAudit.

---

## 10 · Review checklist

- [ ] Root router wiring edit merged (`routers.ts`).
- [ ] `schema.ts` merge + `drizzle-kit push` or equivalent.
- [ ] `0130_bayops.sql` applied on staging.
- [ ] Vitest suite green (`pnpm test server/routers/__tests__/bayOps.test.ts`).
- [ ] API-contract regenerated (`pnpm generate:api`).
- [ ] Driver SwiftUI port (screens 039–044) points at `trpc.bayOps.*`.
