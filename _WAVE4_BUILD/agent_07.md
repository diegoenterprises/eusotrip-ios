# Wave-4 Build · Agent #7 · Theme 2.9

**Scope.** Rewrite `feedback.ts`, create `exceptions.ts` + `roadsideTickets.ts`, migration, schema-staging file, three test files.

**Screens backed.** 065 EusoTicket Exception, 065 Help & Support, 066 Feedback and Ratings, 086 Roadside Inspection, 107 Roadside.

---

## Files created / modified

| Path | Kind |
| --- | --- |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/0150_exceptions_roadside.sql` | NEW migration |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/schema.additions.wave4-7.ts` | NEW staging schema |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/feedback.ts` | REWROTE (was 20-line stub) |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/exceptions.ts` | NEW router |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/roadsideTickets.ts` | NEW router |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/__tests__/feedback.test.ts` | NEW tests |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/__tests__/exceptions.test.ts` | NEW tests |
| `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/__tests__/roadside.test.ts` | NEW tests |

---

## Router surface

### feedback.ts (rewritten)
- `submit({ category, rating 1-5, comment?, screen?, contextJson? })` — protected.
- `listMine({ limit?, offset? })` — protected, current user's history.
- `adminList({ category?, minRating?, maxRating?, userId?, startDate?, endDate?, limit?, offset? })` — admin.
- `getSummary()` — admin, aggregate totals + avg rating + byCategory.
- `list(...)`, `respond(...)` — back-compat shims over the old stub API so no existing client breaks.

### exceptions.ts (new)
- `create({ category, severity, title, description?, witnesses?, voiceS3Key?, photoS3Keys[], lat, lng })`.
- `attachEvidence({ exceptionId, kind: 'photo'|'voice'|'doc', s3Key })`.
- `close({ exceptionId, resolution })`.
- `listMine({ status? })`.
- `getById({ exceptionId })` — returns row **plus** nested `evidence[]`; admin or owner only.

### roadsideTickets.ts (new)
- `list({ status? })`.
- `getById({ ticketId })`.
- `create({ category, location, description })` — canonical; `category` enum now includes **`glass`** (was missing from `driverMobile.getRoadsideAssistance`).
- `update({ ticketId, patch: { status?, description?, location?, resolution? } })`.
- `close({ ticketId, resolution })`.
- `policyForCarrier({ carrierId })` — zero-coverage shell when no row.

---

## Required follow-up edits (STRICT RULE: not done here)

The build agent's scope forbids editing `server/routers.ts`, `drizzle/schema.ts`, and the api-contract index. The following one-line patches must be applied in the integration PR:

### 1 · `server/routers.ts`
Add imports and wire the routers:
```ts
import { feedbackRouter } from "./routers/feedback";
import { exceptionsRouter } from "./routers/exceptions";
import { roadsideTicketsRouter } from "./routers/roadsideTickets";
```
Register:
```ts
export const appRouter = router({
  // …existing…
  feedback: feedbackRouter,          // already present — still named 'feedback'
  exceptions: exceptionsRouter,      // NEW namespace
  roadsideTickets: roadsideTicketsRouter, // NEW namespace
});
```
`feedback` is already registered against the old stub — the rewrite keeps the same export name so no rename is needed.

### 2 · `drizzle/schema.ts`
Copy the five `mysqlTable` blocks from `drizzle/schema.additions.wave4-7.ts` into `schema.ts` (place next to `incidents` at ~line 1515) and delete the staging file afterwards. Also re-export the enum tuples from `schema.ts` so routers can drop the `.additions.wave4-7` import path:
```ts
export { feedback, exceptions, exceptionEvidence, roadsideTickets, roadsidePolicies };
export { FEEDBACK_CATEGORIES, EXCEPTION_CATEGORIES, EXCEPTION_SEVERITIES,
         EXCEPTION_STATUSES, EXCEPTION_EVIDENCE_KINDS,
         ROADSIDE_CATEGORIES, ROADSIDE_STATUSES };
```

### 3 · api-contract index (shared/apiContract.ts or equivalent)
Add the three namespaces to the published contract. Names:
- `feedback.{submit, listMine, adminList, getSummary, list, respond}`
- `exceptions.{create, attachEvidence, close, listMine, getById}`
- `roadsideTickets.{list, getById, create, update, close, policyForCarrier}`

### 4 · `drizzle/migrations/meta/*_journal.json`
Run `drizzle-kit generate` — the migration number `0150` is consistent with the existing sequence (gap after 0100 is preserved).

### 5 · `driverMobile.ts`
Annotate `getRoadsideAssistance` with a `@deprecated use roadsideTickets.create` JSDoc tag. Do not delete — legacy callers still reference the `ticketId: "RSA_N"` return shape.

---

## Schema notes

- `exceptions.severity` is an enum `low|medium|high|critical` — roadmap said "severity ENUM" without an explicit value list, so I picked the project-standard 4-level ladder used in `zeunBreakdownReports.severity`. Adjust if the UI copy diverges.
- `exceptions.witnesses` is JSON of `[{ name, phone?, role? }]` — matches the Figma witness row (name + role chip).
- `roadside_tickets.status` is a 7-state enum rather than the 2-state `open|closed` used for `exceptions`. Screen 107's dark variant renders a `dispatched → in_progress → resolved` timeline, so collapsing to two states would break the UI.
- `roadside_policies` has `carrier_id` as PK (one-row-per-carrier), matching the "Primary coverage card (FleetNet)" on screen 107.

---

## Test notes

Tests mock `getDb` to `null` and smoke-check:
- Zod enum/bounds rejection (category, rating, GPS, kind).
- Admin-gating on `feedback.adminList` and `feedback.getSummary`.
- Empty-shape returns from all `list*` procedures when DB is down.
- Presence of the `glass` category in `roadsideTickets.create`.

Full integration tests (real DB, evidence-attachment lifecycle, ownership FORBIDDEN paths) should be layered on in the drizzle test bed once tables exist.

---

## Lines of code

| File | LOC |
| --- | ---: |
| feedback.ts | 221 |
| exceptions.ts | 210 |
| roadsideTickets.ts | 252 |
| schema.additions.wave4-7.ts | 185 |
| 0150_exceptions_roadside.sql | 98 |
| feedback.test.ts | 86 |
| exceptions.test.ts | 86 |
| roadside.test.ts | 68 |
| **Total** | **~1,206** |
