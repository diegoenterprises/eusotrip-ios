# Wave-4 Build · Agent #3 — Theme 2.4 "Telemetry router family"

**Run:** 2026-04-18
**Scope:** Close the trailer / tank / scale / fuel-tank-status telemetry gap
called out in Wave-3 audit reports `agent_00.md`, `agent_01.md`,
`agent_07.md`, and `agent_09.md` (Master Roadmap §2.4).
**Backend root:** `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend`

---

## 1 · Files created

| Path | Purpose |
|---|---|
| `server/routers/telemetry/trailer.ts` | `getSnapshot({ trailerId })` + gateway-guarded `ingestEvent` |
| `server/routers/telemetry/tank.ts` | `getLoadingSnapshot({ loadId })` + `getHistory({ loadId, limit })` |
| `server/routers/telemetry/scales.ts` | `recordWeigh({ loadId, axle, gross, lat, lng, … })` + `listWeighs({ loadId })` |
| `server/routers/telemetry/index.ts` | Grouped re-export as `telemetryRouter` (sub-routers: `trailer`, `tank`, `scales`) |
| `server/routers/__tests__/telemetry.test.ts` | Vitest unit tests — router shape + input-validation + DB-null fallback |
| `drizzle/0120_telemetry.sql` | MySQL migration: `telemetry_events`, `tank_snapshots`, `fuel_price_locks` |
| `drizzle/schema.additions.wave4-3.ts` | Drizzle staging file (table defs + inferred types + literal tuples) |

## 2 · Files modified

| Path | Change |
|---|---|
| `server/routers/fuel.ts` | Imported `fuelPriceLocks` + `FUEL_GRADES` from the wave-4-3 additions file, then **appended** two new procedures (`getTankStatus`, `lockPrice`) to the existing `fuelRouter` object. No other procedures touched. |

---

## 3 · tRPC procedure surface added

```
telemetry.trailer.getSnapshot    (query)   isolated/protected
telemetry.trailer.ingestEvent    (mutation) gateway-guarded (public + shared-secret)
telemetry.tank.getLoadingSnapshot(query)   isolated/protected
telemetry.tank.getHistory        (query)   isolated/protected
telemetry.scales.recordWeigh     (mutation) isolated/protected
telemetry.scales.listWeighs      (query)   isolated/protected
fuel.getTankStatus               (query)   isolated/protected
fuel.lockPrice                   (mutation) isolated/protected
```

## 4 · Gateway-procedure note

`_core/trpc.ts` does **not** currently export a `gatewayProcedure`.
Per the build rules I fell back to `publicProcedure.use(...)` with a
shared-secret middleware that validates the
`x-telemetry-gateway-secret` request header against the
`TELEMETRY_GATEWAY_SECRET` env var. The middleware is inlined inside
`telemetry/trailer.ts` (marked with a swap-point comment). When a
central `gatewayProcedure` is introduced, replace lines 34-55 in that
file with a single `import { gatewayProcedure } from "../../_core/trpc";`.

## 5 · Changelog — required follow-ups (NOT done per strict rules)

These edits are **out of scope** for this agent but are required before
the router family will be reachable from the mobile client:

1. **`server/routers.ts`** — add:
   ```ts
   import { telemetryRouter } from "./routers/telemetry";
   // ... inside appRouter object:
   telemetry: telemetryRouter,
   ```
2. **`drizzle/schema.ts`** — merge the three tables from
   `drizzle/schema.additions.wave4-3.ts` into the main schema (append at
   end of file; no existing table is mutated). Also re-export the literal
   tuples `TELEMETRY_ENTITY_TYPES` and `FUEL_GRADES`.
3. **api-contract `index.ts`** (the generated tRPC client barrel) —
   regenerate after the `routers.ts` edit so `trpc.telemetry.*` and
   `trpc.fuel.getTankStatus` / `trpc.fuel.lockPrice` become callable from
   the SwiftUI layer.
4. **Add `TELEMETRY_GATEWAY_SECRET`** to the infra env + secrets vault
   (staging + prod). Without it, `telemetry.trailer.ingestEvent` fails
   closed with `INTERNAL_SERVER_ERROR` — the intended behaviour but
   noisy until the env is set.
5. **`_core/trpc.ts`** — consider exporting a shared `gatewayProcedure`
   helper so future MQTT/webhook ingest endpoints can use a single
   auth surface.

## 6 · Schema · new tables (MySQL, utf8mb4 / InnoDB)

### `telemetry_events`
Generic sensor/ELD event stream.
Columns: `id BIGINT PK`, `entity_type ENUM('trailer','tank','scale','vehicle','driver')`, `entity_id VARCHAR(64)`, `kind VARCHAR(64)`, `payload JSON`, `captured_at DATETIME(3)`, `ingested_at DATETIME(3)`, `idempotency_key VARCHAR(128) UNIQUE`, `source VARCHAR(64)`.
Indexes: `(entity_id, captured_at DESC)`, `(entity_type, captured_at DESC)`, `kind`.

### `tank_snapshots`
Current-state row per tank-monitor sample.
Columns: `id`, `load_id INT FK→loads(id) ON DELETE CASCADE`, `fill_pct DECIMAL(5,2)`, `flow_rate DECIMAL(8,2)`, `pressure_psi DECIMAL(8,2)`, `temp_c DECIMAL(6,2)`, `grounded TINYINT(1)`, `vapor_boot_engaged TINYINT(1)`, `captured_at DATETIME(3)`, `created_at`.
Indexes: `(load_id, captured_at DESC)`.

### `fuel_price_locks`
Driver-side price lock (no actual payment).
Columns: `id`, `driver_id INT`, `station_id VARCHAR(64)`, `grade ENUM('diesel','def','gasoline')`, `gallons DECIMAL(10,2)`, `locked_price_cents INT`, `valid_until DATETIME`, `consumed_at DATETIME`, `fuel_transaction_id INT`, `created_at`.
Indexes: `(driver_id, valid_until)`, `station_id`, `consumed_at`.

## 7 · How to run tests

```bash
cd frontend
npx vitest run server/routers/__tests__/telemetry.test.ts
```

Tests pass without a live MySQL — they exercise router shape, Zod
input validation, and the DB-null (`getDb()` returns null) branch.
Coverage includes: gateway-secret rejection paths, axle enum/range
validation on `recordWeigh`, lat/lng bounds, and limit caps on
`listWeighs`/`tank.getHistory`.

## 8 · Figma screens unblocked

- **016 Pickup Loading** — `telemetry.tank.getLoadingSnapshot`
- **030 Loading Locked** — fill/flow/pressure pills + `grounded` chip
- **085 Tank Monitor** — live tank widget
- **101 Weigh Capture** — `telemetry.scales.recordWeigh` + `listWeighs`
- **117 Route Overview / 119 Fuel Stops** — `fuel.getTankStatus` range tile, `fuel.lockPrice` CTA
- **118 Traffic** — trailer `abs` / tire-PSI chips via `telemetry.trailer.getSnapshot`

## 9 · Summary (under 300 words)

Built the complete telemetry router family for Wave-4 Theme 2.4 without
touching `server/routers.ts`, `drizzle/schema.ts`, or the api-contract
barrel (per strict rules). Added a new `server/routers/telemetry/`
directory with three tRPC v11 sub-routers (`trailer`, `tank`, `scales`)
plus an `index.ts` that re-exports them as a grouped `telemetryRouter`.
Each sub-router follows the shape of `scales.ts` / `fuel.ts`
(`isolatedProcedure as protectedProcedure`, `router` from `_core/trpc`,
zod inputs, `getDb()` null-safe paths, structured logger on error).

Extended `fuel.ts` by appending `getTankStatus` (reads latest
`telemetry_events.fuel.level`, falls back to last-purchase heuristic,
computes range via rolling 90-day fleet MPG × tank capacity) and
`lockPrice` (writes a `fuel_price_locks` row with a 15-minute TTL;
no payment captured here).

Authored migration `0120_telemetry.sql` with three tables
(`telemetry_events`, `tank_snapshots`, `fuel_price_locks`), all
indexes required by the spec, a unique constraint on
`idempotency_key`, and a `(driver_id, valid_until)` index on locks.
Staged drizzle definitions in `drizzle/schema.additions.wave4-3.ts`.

Ingestion uses a shared-secret gateway middleware because `_core/trpc.ts`
does not yet export a `gatewayProcedure`; this is flagged in the
changelog with a concrete swap-point.

Wrote Vitest coverage for router shape, input validation, the DB-null
branch, gateway-secret rejection, and bounds checks. Tests run green
without MySQL.

Follow-ups are enumerated in §5 of this report — they touch the three
forbidden files (`routers.ts`, `schema.ts`, api-contract index) plus a
one-line secrets-vault entry.
