# Wave-4 Build · Agent #1 · Theme 2.2 — Changelog

**Theme:** Extend `loadLifecycle.ts` state machine + `loadStatus` enum for tanker sub-states.
**Build date:** 2026-04-18
**Audit source:** `_WAVE3_AUDIT/_MASTER_ROADMAP.md` §2.2, `_WAVE3_AUDIT/agent_01.md`, `_WAVE3_AUDIT/agent_02.md`.

---

## 1 · Sources read (cite-trail)

| Path | Lines read | Purpose |
| --- | --- | --- |
| `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE3_AUDIT/_MASTER_ROADMAP.md` | 1-239 (full) | Theme 2.2 scope + attack order |
| `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE3_AUDIT/agent_01.md` | 1-488 (full) | Driver screens 023-035 tanker sub-state list |
| `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE3_AUDIT/agent_02.md` | 1-443 (full) | Driver screens 036-048 discharge/disconnect sub-state list |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/schema.ts` | 260-320 (loads table + status enum at L277-287) | Enum authority + column list |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/loadLifecycle.ts` | 1-100 (imports + notification map) and 2120-2199 (router shape) | Router idiom + `loadLifecycleRouter` export |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/_core/trpc.ts` | 1-200 (router, protectedProcedure, roleProcedure, ROLES) | Role procedure factory |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/adr.ts` | 1-50 | `roleProcedure` call-site pattern |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/__tests__/users.test.ts` | 1-62 (full) | Vitest + `appRouter.createCaller` test pattern |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/0008_load_lifecycle_states.sql` | 1-93 (full) | Existing enum + `load_state_transitions` audit table |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers.ts` | 182, 1407 | Existing `loadLifecycleRouter` registration points |

---

## 2 · Files created

| Path | Purpose | LOC |
| --- | --- | --- |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/0100_loadlifecycle_tanker_states.sql` | MySQL-compatible migration. `ALTER TABLE loads MODIFY COLUMN status ENUM(...)` to add 11 tanker statuses; adds `tanker_sub_state`, `tanker_sub_state_payload`, `tanker_sub_state_updated_at` columns + index. | 53 |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/schema.additions.wave4-1.ts` | Staging file exporting `TANKER_LOAD_STATUSES` (full enum tuple), `TANKER_ADDED_STATUSES`, `tankerSubStates`, and the `TankerLoadStatus` / `TankerSubState` types. Consumed by the new router; referenced by the schema-patch diff below. | 98 |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/loadLifecycleTanker.ts` | New tRPC v11 sub-router: `TANKER_FSM`, `TANKER_SUB_FSM`, `canTransition()`, `isLegalSubState()`, `getTankerState`, `listAllowedTransitions`, `executeTankerTransition`. `protectedProcedure` for reads, `roleProcedure("DRIVER","DISPATCH")` for transitions. All inputs Zod-validated. Audits to `load_state_transitions` (created in migration 0008). | 299 |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/__tests__/loadLifecycleTanker.test.ts` | Vitest suite: FSM-table shape (no self-loops, no dupes, every new status referenced), sub-state legality, canonical pickup + receiver happy paths, illegal-jump rejection, router-surface assertion, Zod input-validation smoke tests via `createCaller`. | 146 |

**Total new code: ~596 LOC across 4 files.**

## 3 · Files modified

**NONE.** Per the strict rules: `server/routers.ts`, `server/routers 2.ts`, and `drizzle/schema.ts` were NOT edited. The required central-file patches are listed as diffs below for manual review.

---

## 4 · Required central-file edits

### 4a · `server/routers.ts`

Append the new router to the import block AND the `appRouter` map:

```diff
@@ server/routers.ts:182 @@
 import { loadLifecycleRouter } from "./routers/loadLifecycle";
+import { loadLifecycleTankerRouter } from "./routers/loadLifecycleTanker";

@@ server/routers.ts:1407 @@
   loadLifecycle: loadLifecycleRouter,
+  loadLifecycleTanker: loadLifecycleTankerRouter,
```

If `server/routers 2.ts` exists as a parallel index, apply the same two-line delta there.

### 4b · `drizzle/schema.ts` (loads.status enum, line 277)

Replace the enum literal tuple with the expanded list. Simplest path: import the tuple from the staging file.

```diff
@@ drizzle/schema.ts:1 @@
 import {
   ...
   mysqlEnum,
   ...
 } from "drizzle-orm/mysql-core";
+import { TANKER_LOAD_STATUSES } from "./schema.additions.wave4-1";

@@ drizzle/schema.ts:277 @@
-    status: mysqlEnum("status", [
-      "draft", "posted", "bidding", "expired",
-      "awarded", "declined", "lapsed", "accepted", "assigned", "confirmed",
-      "en_route_pickup", "at_pickup", "pickup_checkin", "loading", "loading_exception", "loaded",
-      "in_transit", "transit_hold", "transit_exception",
-      "at_delivery", "delivery_checkin", "unloading", "unloading_exception", "unloaded",
-      "pod_pending", "pod_rejected", "delivered",
-      "invoiced", "disputed", "paid", "complete",
-      "cancelled", "on_hold",
-      "temp_excursion", "reefer_breakdown", "contamination_reject", "seal_breach", "weight_violation",
-    ])
+    status: mysqlEnum("status", TANKER_LOAD_STATUSES)
       .default("draft")
       .notNull(),
```

Also add the three new columns near the bottom of the `loads` table definition (they are introduced by migration 0100 and should match in Drizzle):

```ts
tankerSubState: varchar("tanker_sub_state", { length: 40 }),
tankerSubStatePayload: json("tanker_sub_state_payload").$type<Record<string, unknown>>(),
tankerSubStateUpdatedAt: timestamp("tanker_sub_state_updated_at"),
```

---

## 5 · New tanker statuses added

Eleven new values (ordered by typical lifecycle position):

`locked`, `backing_in`, `brakes_set`, `connecting`, `loading_locked`, `load_locked_filled`, `discharging`, `vapor_purging`, `disconnecting`, `detaching`, `released`.

These cover every chip text referenced in agent_01.md §023-035 (LOCKED / BACKING IN / LOADING / LOAD_LOCKED_FILLED / DETACHING) and agent_02.md §036-048 (UNLOADING / DISCHARGING / DISCONNECTING / CONNECTING / RELEASED). The roadmap's explicit list (`LOCKED`, `BACKING_IN`, `LOADING`, `LOAD_LOCKED_FILLED`, `DETACHING`, `UNLOADING`, `DISCONNECTING`, `CONNECTING`) is fully covered — `LOADING` and `UNLOADING` already existed in the enum; all six others are new, plus five UI-implied extras (`brakes_set`, `loading_locked`, `discharging`, `vapor_purging`, `released`).

---

## 6 · How to run

```bash
cd /Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend
pnpm drizzle-kit push      # applies drizzle/0100_loadlifecycle_tanker_states.sql
pnpm test -- loadLifecycleTanker
```

Expected: 10 green tests (3 FSM-shape, 2 sub-state, 4 path-coverage, 1 router-surface, 2 input-validation).

---

## 7 · Blockers / discovered inconsistencies

1. **`server/routers 2.ts`.** Globbing the repo confirms `server/routers.ts` exists but no file matches `server/routers 2.ts` at the web-repo root. The strict rule forbids editing it, so this is informational only — if the file exists elsewhere it still needs the same two-line patch from §4a.
2. **Enum ordering is load-bearing for MySQL.** MySQL stores enums by numeric index. Migration 0100 inserts the new values into the *middle* of the list (for readability) but MySQL will allocate them new indices at the end regardless — safe, but anyone writing a second migration against this enum should use `SHOW CREATE TABLE loads` before assuming order.
3. **`tanker_sub_state` column is Drizzle-unaware.** Until `schema.ts` is patched (per §4b), the router reads/writes those columns via raw `db.execute(sql\`...\`)`. Tests mock this transparently; production is correct but type-safety is partial until the schema patch lands.
4. **Parent `loadLifecycle.ts` state machine.** This wave deliberately did NOT touch `server/services/loadLifecycle/stateMachine.ts` (the 37-state generic engine). The tanker sub-router operates in parallel; a follow-up wave should reconcile so that `loadLifecycleRouter.transitionState` and `loadLifecycleTankerRouter.executeTankerTransition` share a single guard table.
5. **ROLE name.** Existing `ROLES` map uses `DISPATCH`, not `DISPATCHER` as specified in the task brief. The router uses `roleProcedure("DRIVER","DISPATCH")` to match the actual RBAC constant — adjust your test harness accordingly if it was stubbing `DISPATCHER`.

---

*End of Wave-4 Build Agent #1 changelog.*
