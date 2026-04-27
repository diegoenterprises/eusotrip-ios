# Wave-4 Build · Agent #8

**Theme:** 2.10 Availability / scheduling / utilization
**Secondary gap:** "no `dvir` router" (from `_WAVE3_AUDIT/agent_05.md:386, 391, 408, 413`)

**Backs Figma screens:**
- 083 Schedule Availability (primary)
- 077 Vehicle Trailer (DVIR CTA)
- 078 Home Compliance (utilization + DVIR badge)
- 087 DVIR Builder
- 104 DVIR (post-trip detail)

---

## 1. Files produced

| Path | Purpose |
| --- | --- |
| `server/routers/availability.ts` | New router — weekly grid, blockTime / unblockTime, weekly pattern CRUD, utilization, ICS export |
| `server/routers/dvir.ts` | New router — listMine / getById / create / update / submit / export; integrates with legacy inspections router |
| `server/routers/__tests__/availability.test.ts` | Vitest suite — 7 scenarios |
| `server/routers/__tests__/dvir.test.ts` | Vitest suite — 6 scenarios |
| `drizzle/0160_availability_dvir.sql` | Migration — 4 tables |
| `drizzle/schema.additions.wave4-8.ts` | Drizzle schema types (not merged into `schema.ts` per STRICT rules) |

---

## 2. Migration summary (`drizzle/0160_availability_dvir.sql`)

Four tables, all idempotent (`CREATE TABLE IF NOT EXISTS`):

1. **`driver_availability_blocks`** — ad-hoc blocked windows.
   - `id, driver_id, company_id, from_ts, to_ts, reason, source, created_at`
   - Indexes: `dab_driver_idx`, `dab_company_idx`, `dab_window_idx`
   - CHECK: `to_ts > from_ts`
2. **`driver_weekly_availability`** — recurring weekly pattern.
   - `id, driver_id, company_id, day_of_week, start_min, end_min, updated_at`
   - Unique: `(driver_id, day_of_week, start_min)`
   - CHECK: `day_of_week BETWEEN 0 AND 6`, `start_min >= 0 AND end_min <= 1440`, `end_min > start_min`
3. **`dvirs`** — Wave-4 canonical DVIR.
   - `id, driver_id, vehicle_id, trailer_id, company_id, kind ENUM('pre','post'), status ENUM('draft','submitted'), defects JSON, signatures_s3_key, inspection_ref_id, legacy_dvir_id, created_at, submitted_at`
   - The `inspection_ref_id` and `legacy_dvir_id` columns link to the legacy rows created by `server/routers/inspections.ts:143-189, 279-315` so existing UI keeps working during the transition.
4. **`driver_export_tokens`** — shared bookkeeping for signed-URL exports (availability ICS and DVIR PDF).

---

## 3. Router surface

### `availability.ts`

| Procedure | Kind | Purpose |
| --- | --- | --- |
| `getWeeklyGrid({ weekStartISO })` | query | 7 × 24 grid with per-cell `{available, blocked, offDuty, reason}` — fuses weekly pattern + ad-hoc blocks + `hos_logs` off-duty / sleeper intervals |
| `blockTime({ fromISO, toISO, reason })` | mutation | Inserts ad-hoc block row, returns `id` |
| `unblockTime({ blockId })` | mutation | Deletes the row if it belongs to the calling driver |
| `setAvailability({ dayOfWeek, slots })` | mutation | Replaces the recurring pattern for that day; rejects overlapping slots |
| `getUtilization({ weekStartISO })` | query | Returns `{availableMin, drivingMin, utilization, utilizationPct}`; falls back to `null` if `hos_logs` is unreachable |
| `exportICS({ weekStartISO? })` | mutation | Mints a signed URL (`/api/exports/availability/<token>.ics`), 15-min TTL, writes token to `driver_export_tokens` |

### `dvir.ts`

| Procedure | Kind | Purpose |
| --- | --- | --- |
| `listMine({ vehicleId?, status?, limit? })` | query | Returns Wave-4 rows plus legacy `dvir_reports` fallback (see `inspections.ts:317-338`) |
| `getById({ dvirId })` | query | Wave-4 rows only; scoped to calling driver |
| `create({ vehicleId, trailerId?, kind, defects[], signaturesS3Key? })` | mutation | Inserts as `draft` |
| `update({ dvirId, patch })` | mutation | Patches `trailerId` / `defects` / `signaturesS3Key`; CONFLICT once submitted |
| `submit({ dvirId })` | mutation | Sets `status='submitted'`, `submitted_at=now()`, idempotent; mirrors `inspections.ts:167-170` gamification dispatch when no OOS defects |
| `export({ dvirId })` | mutation | Signed PDF URL (`/api/exports/dvir/<token>.pdf`), 15-min TTL |

### Integration cites (lines in `server/routers/inspections.ts`)

- `inspections.ts:143-189` — `submit` (writes `inspections` row with `type='dvir'`, fires gamification event). Our `dvir.submit` fires the same event via `services/gamificationDispatcher` when the submitted DVIR has no OOS defects.
- `inspections.ts:167-170` — gamification dispatch policy mirrored in `dvir.submit`.
- `inspections.ts:279-315` — `createDVIR` (writes `dvir_reports` + `dvir_defect_items`). Our `dvir.create` writes to `dvirs` and the migration keeps a nullable `legacy_dvir_id` column for backfill.
- `inspections.ts:317-338` — `getDVIRHistory` (legacy list). `dvir.listMine` UNIONs Wave-4 rows with the legacy list so the mobile UI sees both.
- `inspections.ts:340-360` — `reviewDVIR` (mechanic review). Intentionally NOT migrated; mechanic review keeps living on the inspections router until the backfill migration lands.

---

## 4. Changelog — required edits NOT performed (per STRICT rules)

Each item below needs to be applied by a subsequent PR. This agent did **not** edit `server/routers.ts`, `drizzle/schema.ts`, or the api-contract index.

1. `server/routers.ts`
   - Import after existing imports (alphabetical block near `inspectionsRouter` on line 37):
     ```ts
     import { availabilityRouter } from "./routers/availability";
     import { dvirRouter } from "./routers/dvir";
     ```
   - Register inside the top-level `router({ ... })` block (alongside `inspections: inspectionsRouter,` at line 931):
     ```ts
     availability: availabilityRouter,
     dvir: dvirRouter,
     ```
2. `drizzle/schema.ts`
   - Merge the four tables from `drizzle/schema.additions.wave4-8.ts` into the main schema file (pasted as-is — the column names, indexes, and types are drop-in). After merging, delete `schema.additions.wave4-8.ts` and update the import path in both new routers from `'../../drizzle/schema.additions.wave4-8'` to `'../../drizzle/schema'`.
3. `shared/api-contract.ts` (or equivalent tRPC contract index)
   - Add the new namespaces so the mobile client types pick them up:
     ```ts
     availability: AvailabilityRouter;
     dvir: DvirRouter;
     ```
4. Signed-URL server (out of scope for this agent)
   - `/api/exports/availability/:token.ics` — read `driver_export_tokens` by token + kind, render the driver's weekly pattern as VEVENT blocks, stream the ICS.
   - `/api/exports/dvir/:token.pdf` — read `driver_export_tokens` by token + kind, render the submitted DVIR row.

---

## 5. Conflict resolution with `hos_logs`

`getWeeklyGrid` and `getUtilization` both hit `hos_logs` via raw SQL rather than importing the drizzle symbol. This keeps the router self-contained — `hos_logs` lives in the central schema and the STRICT rules forbid editing it. The raw SQL is guarded with `try/catch` so the router remains usable when the hos ingestion pipeline is offline.

**Reason:**
- A cell in `getWeeklyGrid` is only marked `available` if it's inside a weekly slot AND outside every ad-hoc block AND outside every `off_duty`/`sleeper` `hos_logs` interval.
- `getUtilization` divides `driving` minutes (from `hos_logs`) by `netAvailable` (weekly pattern minus blocks).

---

## 6. Tests

- `availability.test.ts` — 7 scenarios (grid shape, block round-trip, inverted window rejection, overlapping slot rejection, overwrite semantics, utilization ratio, signed URL).
- `dvir.test.ts` — 6 scenarios (create, update while draft, submit idempotency, update CONFLICT post-submit, export BAD_REQUEST → signed URL, listMine).

Tests use a lightweight in-memory DB stub so they run in `vitest` without MySQL. Routers are wired via a thin `initTRPC` adapter inside the test file.

---

## 7. Known follow-ups (out of this agent's scope)

- Legacy backfill migration `0161_dvir_backfill.sql` — copy `dvir_reports` rows into `dvirs` with `legacy_dvir_id` set, then deprecate the legacy table after 2 weeks.
- Mechanic review on the new `dvirs` table — currently stays on `inspections.reviewDVIR`; Wave-5 can add `dvir.review` with a proper role check.
- ICS rendering + PDF rendering workers — token plumbing is in place, bytes are not.
- Mobile SwiftUI views for 083 Schedule Availability — this agent delivered backend only.

---

**Output report path:** `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/agent_08.md`
