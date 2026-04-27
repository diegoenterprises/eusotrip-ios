# Wave-4 Build Agent #10 — Theme 2.11 Financial composition / settlement detail

**Scope:** Extend `server/routers/earnings.ts` (composition, goals, atomic trip-wrap) and `server/routers/taxReporting.ts` (1099 download, 1040-ES quarterly).

**Roadmap anchor:** `_WAVE3_AUDIT/_MASTER_ROADMAP.md` §2.11 (line 150).

**Bucket sources:**
- `_WAVE3_AUDIT/agent_03.md` — 054 HaulPay Settlement (GAP item 3 closed), 055 Day Close.
- `_WAVE3_AUDIT/agent_06.md` — 089 Earnings Detail (GAP items 1/2/3 closed).
- `_WAVE3_AUDIT/agent_05.md` — 073 Tax & 1099 (GAP item 3 closed).
- `_WAVE3_AUDIT/agent_07.md` — 092 Settlement Detail (GAP item 1 closed), 093 Tax Vault (GAP items 1/2 closed), 099 Trip Wrap.

---

## 1 · Files created (NONE of which replace existing files)

| Path (relative to repo root) | Purpose |
| --- | --- |
| `server/routers/earnings.append.ts`          | Append-only patch with `earningsWave4Procedures` + types. |
| `server/routers/taxReporting.append.ts`      | Append-only patch with `taxReportingWave4Procedures`. |
| `drizzle/schema.additions.wave4-10.ts`       | `earningsCompositionSnapshots`, `earningsGoals`, `earningsGoalPeriodEnum`. |
| `drizzle/0180_earnings_tax.sql`              | Migration — creates the two tables, the enum, and the `tax_forms(user_id, year, kind)` index conditionally. |
| `__tests__/earnings.composition.test.ts`     | `getComposition` + `atomicTripWrapSubmit` coverage. |
| `__tests__/earnings.goal.test.ts`            | `setGoal` / `getGoal` / `getGoalProgress` coverage. |
| `__tests__/taxReporting.wave4.test.ts`       | `download1099` + `estimateQuarterly` coverage. |

Absolute paths (current Wave-4 staging):

```
/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/server/routers/earnings.append.ts
/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/server/routers/taxReporting.append.ts
/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/drizzle/schema.additions.wave4-10.ts
/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/drizzle/0180_earnings_tax.sql
/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/__tests__/earnings.composition.test.ts
/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/__tests__/earnings.goal.test.ts
/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD/__tests__/taxReporting.wave4.test.ts
```

---

## 2 · New procedures

### `earnings.*` (Theme 2.11)
| Name | Kind | Input | Output |
| --- | --- | --- | --- |
| `getComposition` | query | `{ loadId: uuid }` | `{ loadId, currency, linehaulCents, fscCents, detentionCents, accessorials[], deductions[], adders[], grossCents, netCents, snapshottedAt }` |
| `getGoal` | query | `{ period?: 'week'|'month' }` | `{ goals: EarningsGoal[] }` |
| `setGoal` | mutation | `{ period, targetCents (1..100_000_00) }` | `{ ok, period, targetCents }` |
| `getGoalProgress` | query | `{ period: 'week'|'month' }` | `{ goal, actualCents, paceCents, onTrack, periodStart, periodEnd, elapsedFraction }` |
| `atomicTripWrapSubmit` | mutation | `{ loadId, finalDocsS3Keys, acceptedDeductions[], disputes[] }` | `{ ok, load, composition, acceptedDeductionsCount, disputesCount }` |

### `taxReporting.*` (Theme 2.11)
| Name | Kind | Input | Output |
| --- | --- | --- | --- |
| `download1099` | query | `{ year, kind?: 'NEC'|'MISC' }` | `{ url, expiresIn, filename, year, kind, status }` |
| `estimateQuarterly` | query | `{ year, quarter: 1|2|3|4 }` | `{ year, quarter, periodStart, periodEnd, dueDate, inputs, breakdown, totalTaxCents, dueCents, recommendedWeeklySetAsideCents, assumptionsVersion }` |

---

## 3 · Existing procedures we compose on (cite)

From `_WAVE3_AUDIT/agent_06.md` §089 and `agent_07.md` §092:
- `earnings.getEarnings` — `frontend/server/routers/earnings.ts:95`
- `earnings.getWeeklySummary` — `earnings.ts:136`
- `earnings.list` — `earnings.ts:178`
- `earnings.getPayStatement` — `earnings.ts:224`
- `earnings.getYTDSummary` — `earnings.ts:244`
- `earnings.getSettlementHistory` — `earnings.ts:265`
- `earnings.getSettlementById` — `earnings.ts:269`
- `earnings.getEarningsSummary` — `earnings.ts:339`
- `taxReporting.getContractorSummary` — `taxReporting.ts:24`
- `taxReporting.generate1099s` — `taxReporting.ts:84`
- `taxReporting.list1099s` — `taxReporting.ts:157`
- `taxReporting.get1099Detail` — `taxReporting.ts:209`
- `taxReporting.getDashboard` — `taxReporting.ts:287`
- `wallet.getSummary` — `wallet.ts:288`
- `loadLifecycle.transitionState` — `loadLifecycle.ts:3021`

Transitive dependencies (logical, not `invoke`): `fscEngine.*`, `accessorial.*`, `detentionAccessorials.*`, `payroll.*`, `ratings.submit` (`ratings.ts:155`).

---

## 4 · Schema changes

Declared in `drizzle/schema.additions.wave4-10.ts`; physical migration in `drizzle/0180_earnings_tax.sql`.

| Object | Type | PK |
| --- | --- | --- |
| `earnings_goal_period` | enum(`week`,`month`) | — |
| `earnings_composition_snapshots` | table(`id`, `load_id`, `snapshot_json`, `created_at`) | `id` |
| `earnings_goals` | table(`driver_id`, `period`, `target_cents`, `set_at`) | composite `(driver_id, period)` |
| `idx_tax_forms_user_year_kind` | index on pre-existing `tax_forms(user_id, year, kind)` | — conditionally created. |

`tax_forms` is a pre-existing table per `agent_05.md §073` and `agent_07.md §093`. The migration checks `information_schema.tables` and silently skips the index if the table is absent in a fresh environment.

---

## 5 · Changelog — edits to sibling files we deliberately did NOT make

Per build brief, this agent does not touch `server/routers.ts`, `server/schema.ts`, or the api-contract index. The downstream schema-owner / routing-owner agents need to apply:

1. **`server/routers.ts`** — inside the existing `earningsRouter = createTRPCRouter({ ... })`, spread `...earningsWave4Procedures` from `./earnings`. Same for `taxReporting`.
2. **`server/schema.ts`** — re-export these tables / enums from `drizzle/schema.additions.wave4-10.ts`:
   - `earningsGoalPeriodEnum`
   - `earningsCompositionSnapshots`
   - `earningsGoals`
3. **`@eusotrip/api-contract` index** — add inferred types for the five earnings procedures and the two taxReporting procedures. Follow the `notifications` Theme 2.7 pattern.
4. **Optional columns on `settlement_line_items`** — `driver_accepted_at TIMESTAMPTZ NULL` to persist `acceptedDeductions` outside the snapshot JSON. The atomic trip-wrap stores the list inside the snapshot JSON today; a dedicated column is preferred for indexing but is not on this theme's critical path.
5. **Optional table `settlement_disputes`** — referenced from `atomicTripWrapSubmit` as an aspiration; kept as a code comment so disputes are only in snapshot JSON for now. Creating the table is Theme 2.11's follow-on work.

---

## 6 · Design notes

- **Snapshot-first reads.** `getComposition` prefers the latest `earnings_composition_snapshots` row if present. This protects the 054 / 055 / 089 / 092 / 099 screens from mid-settlement re-prices. `atomicTripWrapSubmit` writes the authoritative snapshot with `finalDocsS3Keys`, `acceptedDeductions`, and `disputes` folded in.
- **Bucketing rules.** `linehaul` → linehaulCents. `fsc`/`fuel_surcharge` → fscCents. `detention` → detentionCents. `hazmat_premium`/`short_haul_premium`/`layover`/`stop_pay`/`bonus` → adders. `platform_fee`/`factoring_fee`/`escrow`/`chargeback` → deductions (amount absoluted). Everything else → accessorials. `payroll_deductions` rows (federal / FICA / state / lease) fold into deductions.
- **Goal math.** Week = UTC-Monday 00:00 → next UTC-Monday. Month = first-of-month UTC → next first-of-month. `pace = actual / elapsedFraction`. `onTrack = pace ≥ goal * 0.85` (no goal → `true`).
- **1040-ES.** Quarter bounds per IRS Pub 505 irregular windows (Q1 Jan–Mar, Q2 Apr–May, Q3 Jun–Aug, Q4 Sep–Dec). Due dates Apr 15 / Jun 15 / Sep 15 / Jan 15-of-next-year. SE tax 15.3% on 92.35% of net SE earnings; half of SE tax deducts against gross; pro-rata 2026 single standard deduction. Bracket table tagged `assumptionsVersion: 2026-single-filer-v1` so downstream clients can flag staleness.
- **Presigned URL.** `download1099` delegates to `server/lib/s3.getPresignedDownloadUrl` with 15-minute expiry and `Content-Disposition: attachment; filename="1099-<KIND>-<YEAR>.pdf"`.

---

## 7 · Test coverage

| File | Cases |
| --- | --- |
| `earnings.composition.test.ts` | bucketing across every `kind` branch; snapshot persistence; single-snapshot on re-read; cross-driver FORBIDDEN; NOT_FOUND; atomic submit happy path + unknown lineItemId + wrong-status guard. |
| `earnings.goal.test.ts` | upsert; week+month isolation; cross-driver isolation; validation (zero / negative / >$100k); `getGoalProgress` pace + onTrack with fake timers; missing-goal onTrack default. |
| `taxReporting.wave4.test.ts` | 1099 happy path (latest FILED); 404 missing; PRECONDITION on PENDING; cross-user isolation; SE + federal math on $40k; withheld subtraction; zero-earnings returns zero; IRS Pub 505 Q3/Q4 bounds; caller scoping. |

---

## 8 · Follow-up / open items

1. **Shipper rating 4-dimension schema** (099 Trip Wrap) — still a GAP from `agent_07.md §099`; not in scope for this theme.
2. **ESANG tax-explainer cards** (093 Tax Vault) — routed through `esangAI.getCoachCopy` once Theme 2.1 lands.
3. **`settlement_disputes` table** — currently captured in snapshot JSON only.
4. **Driver per-diem / hazmat-equip deduction schema** (`agent_05.md §073` item 2) — owned by a separate finance-side agent.
5. **Bracket table for years other than 2026** — caller must pass `year` and the tax-ops agent maintains a lookup next to `DEFAULT_BRACKETS_2026`.
