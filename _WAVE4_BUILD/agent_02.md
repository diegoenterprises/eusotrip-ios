# Wave-4 Build · Agent #2 · Theme 2.5
## Wire trafficNerve → traffic.* + routing.compareAlternatives / applyReroute + reroute_decisions

**Audit ref:** `_WAVE3_AUDIT/agent_09.md` (Bucket 09 · Navigation / Route Overview / Traffic / Fuel Stops)
**Roadmap ref:** `_WAVE3_AUDIT/_MASTER_ROADMAP.md` § 2.5
**Backend repo:** `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/`

---

## 1 · Summary

Replaced the three `traffic.*` stubs with a real pipe to `hz_road_conditions`
(the table that the autopilot `trafficNerve` agent already writes + reads),
added a route-polyline intersection filter so "ahead on your route" queries
(screen 116, 118) finally return real data, added two brand-new routing
procedures — `compareAlternatives` and `applyReroute` — and created the
`reroute_decisions` table that 118 Traffic's decision log, 117 Route
Overview's "Compare alts" drill-down, and the post-trip closed-loop recap
all need.

`trafficNerve` is a periodic sensory agent, not a callable service module;
there is no standalone `services/trafficNerve.ts` to import. Rather than
introduce a shared module in this wave (which would cross-cut with
autopilot/core/*), this router reads the same table the agent reads
(`hz_road_conditions`) via the same `sql.raw` pattern. A Wave-5 ticket is
proposed in the blockers section to extract a `services/trafficService.ts`
that both the router and the agent can depend on.

---

## 2 · Files created / modified

### Modified
| File | Δ | Before | After | Notes |
|---|---|---:|---:|---|
| `server/routers/traffic.ts` | rewrote | 38 | 415 | Three stubs → `getIncidents` / `getConstruction` / `getDelays` against `hz_road_conditions`, with polyline-intersection filter. Exports `TrafficIncident`, `RouteDelaySummary`, `__traffic_internals` (for tests). |
| `server/routers/routing.ts` | appended | 368 | 605 | Added `compareAlternatives` + `applyReroute` at the bottom (lines ~374–604). Existing procedures untouched. New import: `routes` + `eq` from drizzle. |

### Created
| File | Lines | Purpose |
|---|---:|---|
| `drizzle/0110_traffic_reroute.sql` | 64 | `CREATE TABLE` for `reroute_decisions` + guard-creates `hz_road_conditions` (which never had a migration — it was only `sql.raw`'d by `trafficNerve.ts`). |
| `drizzle/schema.additions.wave4-2.ts` | 118 | Drizzle table defs for `rerouteDecisions` + `hzRoadConditions`, plus public DTO types. Staged for a single reviewed diff into `drizzle/schema.ts`. |
| `server/routers/__tests__/traffic.test.ts` | 227 | Unit tests for polyline parsing, haversine, corridor intersection, incident classification, row normalization, and DB-missing-table graceful degradation. |
| `server/routers/__tests__/routing.reroute.test.ts` | 259 | Tests for `compareAlternatives` ranking contract + `applyReroute` happy path / missing-table error / route-not-found / stay-on-route (alt 0). |

### Report
| File | Lines | Purpose |
|---|---:|---|
| `_WAVE4_BUILD/agent_02.md` | — | This document. |

---

## 3 · Required central-file diffs (DO NOT apply here)

These touch the shared indexes and were left for a reviewed patch:

1. **`drizzle/schema.ts`** — merge in the two tables from
   `drizzle/schema.additions.wave4-2.ts`:
   - `export const rerouteDecisions = mysqlTable("reroute_decisions", …)`
   - `export const hzRoadConditions = mysqlTable("hz_road_conditions", …)`

   Place both in the "routing / navigation" region (immediately after
   `routeWaypoints` on line 2958 of schema.ts). Re-export the inferred
   types so downstream routers can import them. Once merged, update
   `server/routers/traffic.ts` to replace the `sql.raw` query with a
   drizzle-native `db.select().from(hzRoadConditions)` call and drop the
   try/catch around the read path.

2. **`server/routers.ts`** — no change. `trafficRouter` and `routingRouter`
   are already wired at lines 122/1245 and equivalent for routing.

3. **`server/api-contract/*` (if present)** — verify the `TrafficIncident`
   and `RouteAlternativeDTO` shapes are exported from the public API
   contract. They are currently exported from `server/routers/traffic.ts`
   and `drizzle/schema.additions.wave4-2.ts` respectively.

4. **`drizzle/relations.ts`** — optional: add
   `rerouteDecisions → routes (routeId)` and `rerouteDecisions → loads
   (loadId)` relations for richer joins.

---

## 4 · Test run command

```bash
cd /Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend

# Both new suites (pure-logic units + mocked DB path)
npx vitest run server/routers/__tests__/traffic.test.ts \
              server/routers/__tests__/routing.reroute.test.ts
```

The suites mock `server/db` and `server/_core/logger`, so they do not
require a live MySQL connection and can run in CI against a clean checkout.

To run with the full suite:

```bash
npx vitest run
```

---

## 5 · Blockers / follow-ups

1. **`hz_road_conditions` was never in `drizzle/schema.ts`.** It existed
   only as a raw SQL SELECT inside `trafficNerve.ts`. Migration 0110
   guards it with `CREATE TABLE IF NOT EXISTS` to be safe in any
   environment that has already seeded it manually, but the
   **authoritative fix is to merge `schema.additions.wave4-2.ts`**
   into `drizzle/schema.ts` so future drizzle snapshots pick it up.
   Until that happens, `traffic.*` queries run through `sql.raw` and the
   `.catch` in `fetchActiveIncidents` returns `[]` when the table is
   missing.

2. **No shared `trafficService` module.** The closest equivalent is the
   autopilot agent `server/services/autopilot/agents/sensory/trafficNerve.ts`
   (the task brief named this as the expected service path). That file
   is a `BaseAgent` subclass — not a callable module. **Proposal:** in
   Wave-5 extract
   `server/services/trafficService.ts` exposing
   `findActiveIncidents({ bbox?, constructionOnly?, limit? })` and
   `findIncidentsAlongRoute({ routeId, corridorMiles })`. The agent and
   the new `traffic.*` router procedures both depend on it. For now the
   router inlines the query to avoid a premature abstraction.

3. **`compareAlternatives` returns synthesized candidates.** True
   alternates require a server-side HERE/OSRM wrapper. The current
   implementation derives them from the baseline route's
   duration/fuel/miles via 5 hard-coded templates and ranks them by a
   composite score (ETA + fuel × 2 + risk × 30 + positive tolls × 0.5).
   This is enough to unblock the 117 "Compare alts" and 118 "Stay /
   Take Pulaski" UIs but should be replaced with a real multi-route
   call once the HERE server wrapper lands (Wave-5, referenced in
   agent_09.md Top-3 Gap #2).

4. **Polyline intersection uses point-to-point haversine only.** The
   `routes.polyline` column is a 2-point string (`lat,lng;lat,lng`),
   so true segment-to-point distance adds no precision. Once the real
   polyline lands (roadmap item 2.5 #4), swap
   `pointIntersectsPolyline` for a proper perpendicular-distance
   routine. The helper is already factored and unit-tested for easy
   replacement.

5. **Audit-log + approvalGate side effects.** `applyReroute` flows
   through `isolatedProcedure`, so it inherits the autoAudit middleware
   and the approval gate. Drivers whose account is `pending_review`
   will be blocked — verify on staging that the dispatched DRIVER role
   lands in `approved` state before this surface goes live to the
   mobile clients.

6. **`hz_road_conditions.id` column type.** Existing `sql.raw` treats it
   as a generic number. Migration 0110 defines it as `BIGINT`. If any
   live environment already has this table as `INT`, the migration's
   `CREATE TABLE IF NOT EXISTS` will skip — a manual `ALTER` is needed
   there. Low-risk: the trafficNerve agent casts rows to `any`.

---

## 6 · Cross-links

- 116 Navigation: `traffic.getIncidents({ routeId })` now feeds the "2
  AHEAD" incidents counter + the Reroute around CTA.
- 117 Route Overview: `routing.compareAlternatives({ routeId })` feeds
  the ranked alternates panel + "Compare alts" button.
- 118 Traffic: `traffic.getIncidents` → primary incident card; the
  "Stay on 95" / "Take Pulaski" buttons call
  `routing.applyReroute({ routeId, alternativeId, reason })`. Dark-mode
  Decision Log reads directly from `reroute_decisions` (WHERE
  `driver_id = ctx.user.id ORDER BY applied_at DESC`).
- Closes roadmap items 2.5 #1, #2, #3 (partially — full "apply reroute"
  including live polyline swap requires #4 real-road polyline).

**Remaining Bucket-09 gaps not covered by this agent:** tank status
(Theme 2.4 — Agent #3), navigation.getNextManeuver (Theme 2.5 #2 —
future agent), tolls.estimateForRoute (Theme 2.5 #5), fuel
price-lock (Theme 2.7 — future agent).
